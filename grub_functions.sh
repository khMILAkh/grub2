# grub driver for rc-boot

LOADER_CONFIG=/boot/grub/menu.lst


GRUB_Root_convert() 	# This function simply converts the normal Linux
		    	# device name into the form (MajorMinornumber)
			# it is neccesary becouse the bug in grub.
{
	TMP_ROOT_NAME=`basename $1`
	TMP=`echo $TMP_ROOT_NAME | awk '{gsub(/^hd/,"");print $0}'`
	if [ "$TMP_ROOT_NAME" != "$TMP" ]; then 
		ADD=3
		GROOT=$TMP
	fi
	TMP=`echo $TMP_ROOT_NAME | awk '{gsub(/^sd/,"");print $0}'`
	if [ "$TMP_ROOT_NAME" != "$TMP" ]; then 
		ADD=8
		GROOT=$TMP
	fi
	DRIVE=`echo $GROOT| awk '{gsub(/[0-9]*/,"");print $0}'`
	NR=`echo $GROOT| awk '{gsub(/[a-z]*/,"");print $0}'`
	NDRIVE=""
	TR=`echo $DRIVE |tr "a-j" "0-9"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="$TR"
	TR=`echo $DRIVE |tr "k-u" "0-9"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="1${TR}"
	TR=`echo $DRIVE |tr "w-z" "0-3"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="2${TR}"
	if [ "${NDRIVE}" = "" ]; then
		rcboot_message "Error in \"$CONFIG_DIR/images/$NAME\" file improper ROOT option"
		exit 1
	fi
	NDRIVE=`expr $NDRIVE + $ADD`
	[ $NR -lt 10 ] && NR=0${NR}
	echo "${NDRIVE}$NR"
	unset TMP TMP_ROOT_NAME TR NDRIVE GROOT DRIVE ADD NR
}


GRUB_convert()		# This function converts the normal Linux 
			# device name into the stupid grub notation 
			# for example /dev/hda2 = (hd0,2)
{
	GROOT=`basename $1`
 
	GROOT=`echo $GROOT| awk '{gsub(/^hd|^sd/,"");print $0}'` 
	DRIVE=`echo $GROOT| awk '{gsub(/[0-9]*/,"");print $0}'`
	NR=`echo $GROOT| awk '{gsub(/[a-z]*/,"");print $0}'`
	NDRIVE=""
	TR=`echo $DRIVE |tr "a-j" "0-9"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="$TR"
	TR=`echo $DRIVE |tr "k-u" "0-9"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="1${TR}"
	TR=`echo $DRIVE |tr "w-z" "0-3"`
	[ "${DRIVE}" != "$TR" ] && NDRIVE="2${TR}"
	if [ "${NDRIVE}" = "" ]; then
		rcboot_message "Error in \"$CONFIG_DIR/images/$NAME\" file improper ROOT option"
		exit 1
	fi
	if [ "${NR}" != "" ]; then 
		NR=`expr $NR - 1`
		echo "(hd${NDRIVE},$NR)"
	else
		echo "(hd${NDRIVE})"
	fi
	unset TR NR NDRIVE GROOT DRIVE
}


GRUB_COUNTER=0
GRUB_DEF=0

rc_boot_prep_image () {
	if [ "$LILO_ONLY" != "" ] && is_yes "$LILO_ONLY" ; then 
		return 0
	fi
  
	if [ "$NAME" = "$DEFAULT" ] ; then
		GRUB_DEF=$GRUB_COUNTER
		GRUB_COUNTER=$(($GRUB_COUNTER+1))
	fi
}

rc_boot_init () {
	[ "$COLORS" = "" ] && COLORS="white/blue blue/white"
  
	# This is the main part of the /boot/grub/menu.lst
	cat <<!EOF!
# By default boot the $DEFAULT entry
default $GRUB_DEF
# Wait $TIMEOUT seconds for booting
timeout $TIMEOUT
# Fallback to the second entry.
fallback 1
# Dafault colors
color $GRUB_COLORS
!EOF!

	if [ "$PASSWORD" != "" ] ; then 
		echo "#The password:"
		echo "password $PASSWORD"
	fi
}

GRUB_SEPARATE_BOOT=unknown

strip_boot () {
  case $GRUB_SEPARATE_BOOT in
    yes )
      INITRD=$(echo $INITRD | sed -e 's|/boot||')
      KERNEL=$(echo $KERNEL | sed -e 's|/boot||')
      ;;
    no )
      ;;
    * )
      boot=$(get_dev /boot)
      root=$(get_dev /)
      if [ "$boot" != "" -a "$root" != "$boot" ] ; then
        debug "separate boot = yes"
        GRUB_SEPARATE_BOOT=yes
      else
        debug "separate boot = no"
        GRUB_SEPARATE_BOOT=no
      fi
      strip_boot
      ;;
  esac
}

rc_boot_image () {
	if [ "$LILO_ONLY" != "" ] && is_yes "$LILO_ONLY" ; then 
		return 0
	fi
  
	echo "# $TYPE image"
	echo "title $NAME"
	if is_yes "$LOCK" ; then
		echo "lock"
	fi

	strip_boot
  
	case "$TYPE" in
	linux )
		ROOT="root=$(GRUB_Root_convert $ROOT)"
		[ "${VGA}" != "" ] && VGA="vga=${VGA}"
		[ "${APPEND}" != "" ]  && APPEND="append=\"${APPEND}\"" 
		echo kernel "$KERNEL" "$ROOT" "$VGA" "${APPEND}"
		[ "$INITRD" != "" ] && echo "initrd $INITRD"
		;;
	dos | bsd )
		echo "root $(GRUB_convert $ROOT)"
		echo "makeactive"
		echo "chainloader +1"
		;;
	*)	# Buuu 
		die "Don't know how to handle OS type = '$TYPE'"
		;;
	esac
}

rc_boot_fini () {
	echo "# EOF"
}

rc_boot_run () {
	if [ "$GRUB_SEPARATE_BOOT" = yes ] ; then
		# nasty workaround :<<
		mkdir -p /boot/boot/grub || die "cannot create /boot/boot/grub"
		rm -f /boot/boot/grub/menu.lst
		ln /boot/grub/menu.lst /boot/boot/grub/menu.lst

		# this is not part of workaround :^)
		grubdir=/grub
	else
		grubdir=/boot/grub
	fi

	root_drive=$(GRUB_convert $STAGE2)
	install_drive=$(GRUB_convert $BOOT)
  
	debug "root_drive = $root_drive [$STAGE2]"
	debug "install_drive = $install_drive [$BOOT]"
  
	log=`mktemp /tmp/grub.XXXXXX`
	/sbin/grub --batch > $log 2>&1 <<EOF
root $root_drive
setup --stage2=/boot/grub/stage2 --prefix=$grubdir $install_drive
quit
EOF

	if grep -q "Error [0-9]*: " $log ; then
		while read LINE ; do
		msg "grub: $LINE"
		done < $log
		die "grub failed"
	fi

	while read LINE ; do
		debug "grub: $LINE"
	done < $log
  
	rm -f $log
  
	#/sbin/grub-install $BOOT >/dev/null 2>&1
}

# Thats all folk.
