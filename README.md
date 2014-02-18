bhyve-run.sh
============

This is a simple script to install, run and destroy [bhyve](http://bhyve.org)
VMs loaded by [grub2-bhyve](https://github.com/grehan-freebsd/grub2-bhyve). So
this is mainly for non-FreeBSD guests. For FreeBSD guests the official vmrun.sh
(located in /usr/share/examples/bhyve/vmrun.sh) works just fine.

Example
-------

Let's set up a "ubuntu server" VM.

### Step 1

Create an empty directory and create a `bhyve-run.conf` containing the following
data. Of course you'll have to adapt the paths accordingly.

	NAME="ubuntu"
	TAP="tap0"
	IF="lagg0"
	BRIDGE="bridge0"

	IMG="${NAME}.img"
	IMGSIZE="8G"
	ISO=/vms/isos/ubuntu-12.04.4-server-amd64.iso
	MAP=./device.map

	CPUS=1
	MEM=1024

	GRUB_RUN_ROOT="hd0,msdos1"

	GRUB_INSTALL="|less"

	GRUB_RUN=""

### Step 2

Start `bhyve-run.sh` in install mode using `bhyve-run.sh -i`. A second window
will open displaying the grub menu. Make sure your cursor is in the window from
where you started `bhyve-run.sh`, not the window showing the grub menu.
Select the entry you would choose to start the install process and press `e`.
You will be presented with a series of grub commands. Enter the relevant
commands into the `GRUB_INSTALL` variable in the `bhyve-run.conf` file (don't
forget to append `boot`!). Shutdown the current bhyve instance using
`bhyve-run.sh -d`.

My `bhyve-run.conf` looks like this after this step:

	NAME="ubuntu"
	TAP="tap0"
	IF="lagg0"
	BRIDGE="bridge0"

	IMG="${NAME}.img"
	IMGSIZE="8G"
	ISO=/vms/isos/ubuntu-12.04.4-server-amd64.iso
	MAP=./device.map

	CPUS=1
	MEM=1024

	GRUB_RUN_ROOT="hd0,msdos1"

	GRUB_INSTALL="linux /install/vmlinuz
	file=/cdrom/preseed/ubuntu-server.seed quiet --
	initrd /install/initrd.gz
	boot"

	GRUB_RUN=""

### Step 3

Restart `bhyve-run.sh` in in install mode using `bhyve-run.sh -i`. The install
routine should start. After finishing the install, shutdown the current bhyve
instance using `bhyve-run.sh -d`.

### Step 4

You should be able to boot into the VM by running `bhyve-run.sh` (you might have
to change the `GRUB_RUN_ROOT` variable). You will be presented with a text based
grub menu and after selecting the appropriate option boot into the VM. If you
are presented with a graphical boot menu, in a seperate window, enter `|less` in
`GRUB_RUN` variable and proceed with Step 5.

### Step 5 (optional)

Select the entry you want to boot by default (remember to keep the cursor in the
correct window, if you use the `|less` hack together with a graphical grub menu)
and press `e`. Enter the relevant grub commands in the `GRUB_RUN` variable and
add `boot`. Now you can directly boot into the VM using `bhyve-run.sh`. Remember
to clean up the VM using `bhyve-run.sh -d` when it is not longer needed.

My `bhyve-run.conf` looks like this after this step:

	NAME="ubuntu"
	TAP="tap0"
	IF="lagg0"
	BRIDGE="bridge0"

	IMG="${NAME}.img"
	IMGSIZE="8G"
	ISO=/vms/isos/ubuntu-12.04.4-server-amd64.iso
	MAP=./device.map

	CPUS=1
	MEM=1024

	GRUB_RUN_ROOT="hd0,msdos1"

	GRUB_INSTALL="linux /install/vmlinuz
	file=/cdrom/preseed/ubuntu-server.seed quiet --
	initrd /install/initrd.gz
	boot"

	GRUB_RUN="insmod gzio
	insmod part_msdos
	insmod ext2
	set root='(${GRUB_RUN_ROOT})'
	search --no-floppy --fs-uuid --set=root
	021b8c8a-fa59-4e30-b328-515fa86d3c49
	linux        /boot/vmlinuz-3.11.0-15-generic
	root=UUID=021b8c8a-fa59-4e30-b328-515fa86d3c49 ro
	initrd        /boot/initrd.img-3.11.0-15-generic
	boot"

