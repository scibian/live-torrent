#!/bin/sh

PREREQ=""
prereqs()
{
        echo "$PREREQ"
}
case $1 in
# get pre-requisites
prereqs)
        prereqs
        exit 0
        ;;
esac

OPTS="-q"

# Remove old scripts from initrd 
LDIR="/lib/live/boot"
ORIG="9990-mount-http.sh.orig 9990-cmdline-old.orig 9990-overlay.sh.orig 9990-netbase.sh.orig"
for file in ${ORIG}
do
	trgfile=${LDIR}/${file}
	if [ -e ${trgfile} ]; then
		rm -f ${trgfile} 
	fi
done
