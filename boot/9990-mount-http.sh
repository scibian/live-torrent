#!/bin/sh -x

#set -e

do_print_log () {

	type=${1}
	ptime=${2}

	case $type in
		"begin")
			message="DOWNLOAD START AT:" 
		;;
		"end")
			message="DOWNLOAD ELAPSED TIME:"
		;;
		*)
			message=""
		;;
	esac
	if [ ${ptime} -gt 0 ]
        then
                log_success_msg "${message} ${ptime} seconds"
        fi

}

do_get_now ()
{
        mytime=$(date +%s || 0 )
        echo ${mytime}
}


do_get_elapsed () 
{
        ref=${1}
        now=$(do_get_now)

        if [ "${ref}" = "" ] || [ "${now}" = "" ]
        then
                return 1
        fi

        if [ ${now} -gt ${ref} ]
        then
                elap=$(expr ${now} - ${ref})
        else
                elap=0
        fi
        do_print_log "end" ${elap}       
}

do_sync_time () 
{
	if [ -n	"${NTPSERVER}" ]
	then
		/bin/ntpdate ${NTPSERVER} || log_warning_msg "Error: NTP SERVER IS DOWN" 
		if [ -n ${EPOCH} ] 
		then
			while [ $(date +%s) -le ${EPOCH} ]
			do
				sleep 1
			done
		else
			log_warning_msg "Error: EPOCH TIME CANNOT BE NULL"
		fi
		
	else
		log_warning_msg "Error: TIME IS NOT THE SAME IN ALL MACHINES"
	fi
}

do_httpmount ()
{
	rc=1

	for webfile in HTTPFS FTPFS FETCH
	do
		local url extension dest
		url="$(eval echo \"\$\{${webfile}\}\")"
		extension="$(echo "${url}" | sed 's/\(.*\)\.\(.*\)/\2/')"

		if [ -n "$url" ]
		then
			case "${extension}" in
				iso|squashfs|tgz|tar|torrent)
					if [ "${extension}" = "iso" ]
					then
						mkdir -p "${alt_mountpoint}"
						dest="${alt_mountpoint}"
					else
						dest="${mountpoint}/${LIVE_MEDIA_PATH}"
						mount -t ramfs ram "${mountpoint}"
						mkdir -p "${dest}"
					fi
					if [ "${webfile}" = "FETCH" ]
					then
						do_sync_time 					
						case "$url" in
								tftp*)
								ip="$(dirname $url | sed -e 's|tftp://||g' -e 's|/.*$||g')"
								rfile="$(echo $url | sed -e "s|tftp://$ip||g")"
								lfile="$(basename $url)"
								log_begin_msg "Trying tftp -g -b 65464 -r $rfile -l ${dest}/$lfile $ip"
								reftime=$(do_get_now)
								do_print_log "begin" ${reftime}
								tftp -g -b 65464 -r $rfile -l ${dest}/$lfile $ip
								do_get_elapsed ${reftime}
							;;
							xget*)
                                                                ip="$(dirname $url | sed -e 's|xget://||g' -e 's|/.*$||g')"
                                                                server="$(echo $ip | awk -F ':' '{print $1}')"
                                                                isport="$(echo $ip | awk -F ':' '{print $2}')"
                                                                port=${isport:=20004}
                                                                rfile="$(echo $url | sed -e "s|xget://$ip/||g")"
								fpasswd="/etc/passwd"
								fgroup="/etc/group"
								# Dirty hack to prevent segmentation fault #
								if [ ! -e $fpasswd ]
								then
									echo 'root:x:0:0:root:/root:/bin/bash' > $fpasswd
								fi
								if [ ! -e $fgroup ]
								then
									echo 'root:x:0:' > $fgroup
								fi
								# End #
								log_begin_msg "Trying xget -n ${server} -p ${port} -s ${rfile} ${dest}"
								reftime=$(do_get_now)
								do_print_log "begin" ${reftime}
								/bin/xget -n ${server} -p ${port} -s ${rfile} ${dest}
								do_get_elapsed ${reftime}
								rm -f $fpasswd $fgroup
							;;
							http*torrent)
								torrentfile="/tmp/$(basename ${url})"
								log_begin_msg "Trying wget ${url} -O ${torrentfile}"
								wget "${url}" -O "${torrentfile}"
								if [ -e ${torrentfile} ]
								then
									imagefile="${dest}/`/bin/ctorrent -x ${torrentfile} | sed -n "s/<.*> \+\([^ ]*\).*/\1/p"`"
									reftime=$(do_get_now)
									do_print_log "begin" ${reftime}
									/bin/ctorrent ${torrentfile} -s ${imagefile} &
									pidofctorrent="$(pidof ctorrent)"
									cmdexit=1
									sleep 1
									while [ ${cmdexit} -ne 0 ]
									do
										sleep $(tr -cd 1-9 </dev/urandom | head -c 1)
										/bin/ctorrent -c ${torrentfile} -s ${imagefile} | grep -q "100%"
										cmdexit=${?}
									done
									do_get_elapsed ${reftime} 
									kill -HUP ${pidofctorrent}
								else
									MODULES='i8042 atkbd ehci-pci ehci-hcd uhci-hcd ohci-hcd usbhid'
									for mod in ${MODULES}
									do
										modprobe $mod || true
									done
									mkdir -p /var/log
									syslogd -O /var/log/syslog
									REASON="$@" PS1='(livetorrent) ' /bin/sh -i </dev/console >/dev/console 2>&1	
								fi
                                                        ;;
							*)
								log_begin_msg "Trying wget ${url} -O ${dest}/$(basename ${url})"
								reftime=$(do_get_now)
								do_print_log "begin" ${reftime}
								wget "${url}" -O "${dest}/$(basename ${url})"
								do_get_elapsed ${reftime}
								;;
						esac
					else
						log_begin_msg "Trying to mount ${url} on ${dest}/$(basename ${url})"
						if [ "${webfile}" = "FTPFS" ]
						then
							FUSE_MOUNT="curlftpfs"
							url="$(dirname ${url})"
						else
							FUSE_MOUNT="httpfs"
						fi

						if [ -n "${FUSE_MOUNT}" ] && [ -x /bin/mount.util-linux ]
						then
							# fuse does not work with klibc mount
							ln -f /bin/mount.util-linux /bin/mount
						fi

						modprobe fuse
						$FUSE_MOUNT "${url}" "${dest}"
						ROOT_PID="$(minips h -C "$FUSE_MOUNT" | { read x y ; echo "$x" ; } )"
					fi
					[ ${?} -eq 0 ] && rc=0
					[ "${extension}" = "tgz" ] && live_dest="ram"
					if [ "${extension}" = "iso" ]
					then
						isoloop=$(setup_loop "${dest}/$(basename "${url}")" "loop" "/sys/block/loop*" "" '')
						mount -t iso9660 "${isoloop}" "${mountpoint}"
						rc=${?}
					fi
					break
					;;

				*)
					log_begin_msg "Unrecognized archive extension for ${url}"
					;;
			esac
		fi
	done

	if [ ${rc} != 0 ]
	then
		if [ -d "${alt_mountpoint}" ]
		then
		        umount "${alt_mountpoint}"
			rmdir "${alt_mountpoint}"
		fi
		umount "${mountpoint}"
	elif [ "${webfile}"  != "FETCH" ] ; then
		NETBOOT="${webfile}"
		export NETBOOT
	fi

	return ${rc}
}
