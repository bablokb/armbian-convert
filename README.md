armbian-convert
===============

This project provides a imple script `armbian-convert.sh` to convert an
Armbian-image from a single-filesystem image to a two-filesystem image.

Having /boot on a different partition than the rest of the system we can
use [pi-boot-switch](https://github.com/bablokb/pi-boot-switch
"pi-boot-switch") to switch between different installations on
the same sd-card (or even boot from a differen mass-storage device, e.g. a
attached hard-disk).


Installation
------------

Run

    git clone https://github.com/bablokb/armbian-convert.git
    cd armbian-convert
    sudo tools/install

The installation-script just copies the file `files/usr/local/sbin/armbian-convert.sh`
to it's target destination.


Usage
-----

Run

    sudo armbian-convert.sh -h

for a short help.

Run

    sudo armbian-convert.sh -U Armbian.xxx.7z

to convert the image. The converted image is named `Armbian.xxx.new.img`, but you
can pass any other target-image name with the `-o`-option.

Of course you need the 7z-utility and enough space on the device for the extracted
original image and the converted image.

