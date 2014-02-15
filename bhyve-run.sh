#! /bin/sh

# "THE BEER-WARE LICENSE" (Revision 42):
# <tobias.rehbein@web.de> wrote this file. As long as you retain this notice
# you can do whatever you want with this stuff. If we meet some day, and you
# think this stuff is worth it, you can buy me a beer in return.
#                                                              Tobias Rehbein

BHYVE="/usr/sbin/bhyve"
BHYVECTL="/usr/sbin/bhyvectl"
CAT="/bin/cat"
GREP="/usr/bin/grep"
GRUBBHYVE="/usr/local/sbin/grub-bhyve"
ID="/usr/bin/id"
IFCONFIG="/sbin/ifconfig"
KLDSTAT="/sbin/kldstat"
PRINTF="/usr/bin/printf"
SYSCTL="/sbin/sysctl"
TRUNCATE="/usr/bin/truncate"

CONFIG="bhyve-run.conf"

f_load_config () {
	if [ -r "${CONFIG}" ]; then
		. "${CONFIG}"
		return 0
	fi

	return 1
}

f_check_grubbhybe () {
	[ -x "${GRUBBHYVE}" ]
}

f_usage () {
	${CAT} >&2 <<-eom
	bhyve-run.sh - run, install and destroy your grub-bhyve based vms

	bhyve-run.sh -i -- install vm
	bhyve-run.sh -r -- run vm
	bhyve-run.sh -d -- destroy vm

	Options are defined in a local "${CONFIG}" file.
	eom
}

f_if_exists() {
	if ! [ $# -eq 1 ]; then
		echo "missing parameter: f_if_exists <interface>"
		exit 1
	fi

	${IFCONFIG} "$1" >/dev/null
}

f_bridge_has_member() {
	if ! [ $# -eq 1 ]; then
		echo "missing parameter: f_bridge_has_member <interface>"
		exit 1
	fi

	if ! f_if_exists "$1"; then
		return 1
	fi

	${IFCONFIG} ${BRIDGE} | grep -q "member: $1"
}

f_bridge_has_other_members() {
	${IFCONFIG} ${BRIDGE} | \
		grep -v "member: ${IF}" | \
		grep -q "member: "
}

f_setup_network () {
	if ! f_if_exists "${BRIDGE}"; then
		${IFCONFIG} ${BRIDGE} create
	fi

	if ! f_if_exists "${TAP}"; then
		${IFCONFIG} ${TAP} create
	fi

	if ! f_bridge_has_member "${TAP}"; then
		${IFCONFIG} ${BRIDGE} addm ${TAP}
	fi

	if ! f_bridge_has_member "${IF}"; then
		${IFCONFIG} ${BRIDGE} addm ${IF}
	fi

	${SYSCTL} net.link.tap.user_open=1 >/dev/null
	${SYSCTL} net.link.tap.up_on_open=1 > /dev/null

	${IFCONFIG} ${TAP} up
	${IFCONFIG} ${BRIDGE} up
}

f_teardown_network () {
	if f_if_exists "${TAP}"; then
		${IFCONFIG} ${TAP} destroy
	fi

	if ! f_bridge_has_other_members; then
		${IFCONFIG} ${BRIDGE} destroy
	fi

	cat >&2 <<-eom
	You might want to reset the sysctls to 0:

	sysctl net.link.tap.user_open=0
	sysctl net.link.tap.up_on_open=0
	eom
}

f_run_grubbhyve () {
	if ! [ $# -eq 1 ]; then
		echo "missing parameter: f_run_grubbhyve <root device>"
		exit 1
	fi

	${GRUBBHYVE} -m "${MAP}" -M "${MEM}" -r "$1" "${NAME}"
}

f_run_bhyve () {
	${BHYVE} -c "${CPUS}" -m "${MEM}" -A -I -H \
		-s 0,hostbridge -s 2,virtio-blk,"${IMG}" \
		-s 3,virtio-net,"${TAP}" -s 4,ahci-cd,"${ISO}" \
		-S 31,uart,stdio "${NAME}"
}

f_vm_running () {
	[ -e "/dev/vmm/${NAME}" ]
}

f_if_active () {
	if ! [ $# -eq 1 ]; then
		echo "missing parameter: f_if_active <interface>"
		exit 1
	fi

	${IFCONFIG} "$1" | grep -q "status: active"
}

f_install_vm () {
	cat >"${MAP}" <<-eof
	(hd0) ${IMG}
	(cd0) ${ISO}
	eof

	${TRUNCATE} -s "${IMGSIZE}" "${IMG}"

	f_setup_network

	${PRINTF} "c\n%s\n" "${GRUB_INSTALL}" | \
		f_run_grubbhyve "cd0"

	f_run_bhyve
}

f_run_vm () {
	if f_vm_running; then
		echo "VM is already running." >&2
		exit 1
	fi

	if f_if_active "${TAP}"; then
		echo "Interface ${TAP} already in use." >&2
		exit 1
	fi

	if [ ! \( -r "${MAP}" -a -r "${IMG}" \) ]; then
		echo "VM seems not to be installed." >&2
		exit 1
	fi

	f_setup_network

	${PRINTF} "c\n%s\n" "${GRUB_RUN}" | \
		f_run_grubbhyve "${GRUB_RUN_ROOT}"

	f_run_bhyve
}

f_destroy_vm () {
	if f_vm_running; then
		${BHYVECTL} --destroy --vm="${NAME}"
	fi

	f_teardown_network
}

if ! ${KLDSTAT} -v | ${GREP} -q "vmm"; then
	${CAT} >&2 <<-eom
	"vmm.ko" has to be loaded. To do so, run:

	kldload vmm
	eom

	exit 1
fi

if ! [ $(${ID} -u) -eq 0 ]; then
	echo "You must be root to run this script." >&2

	exit 1
fi

if ! [ -x "${GRUBBHYVE}" ]; then
 	${CAT} >&2 <<-eom   
	grub-bhyve loader not. You can install it using something along the
	lines of:

	cd /usr/ports/sysutils/grub2-bhyve
	make install clean
	eom

	exit 1
fi

if ! f_load_config; then
	${CAT} >&2 <<-eom
	Configuration file "${CONFIG}" not found.

	Example:

	cat >${CONFIG} <<eof
	NAME="ubuntu"
	TAP="tap0"
	IF="lagg0"
	BRIDGE="bridge0"

	IMG="\${NAME}.img"
	IMGSIZE="8G"
	ISO=./ubuntu.iso
	MAP=./device.map

	CPUS=2
	MEM=2048

	GRUB_INSTALL="linux /install/vmlinuz file=/cdrom/preseed/ubuntu-server.seed
	quiet --
	initrd /install/initrd.gz
	boot"

	GRUB_RUN="insmod gzio
	insmod part_msdos
	insmod ext2
	set root='(hd0,msdos1)'
	search --no-floppy --fs-uuid --set=root 021b8c8a-fa59-4e30-b328-515fa86d3c49
	linux        /boot/vmlinuz-3.11.0-15-generic
	root=UUID=021b8c8a-fa59-4e30-b328-515fa86d3c49 ro
	initrd        /boot/initrd.img-3.11.0-15-generic
	boot"

	eof	
	eom

	exit 1
fi


if [ $# -eq 0 ]; then
	f_usage
	exit 1
fi

while getopts "ird" opt; do
	case $opt in
	i)
		f_install_vm
		;;
	r)
		f_run_vm
		;;
	d)
		f_destroy_vm
		;;
	h)
		f_usage
		exit 0
		;;
	*)
		f_usage
		exit 1
		;;
	esac
done
