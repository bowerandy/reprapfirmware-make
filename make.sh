#!/bin/bash
#----------------------------------------------------------------------------
#
# Builds RepRapPro and DC42's Ormerod firmware from source
#
# - Downloads Arduino environment from arduino.cc
# - Downloads the selected firmware from github.com
# - Compiles the RepRapFirmware source code
#
# Hope this works for you too :D
#
# 3D-ES
#----------------------------------------------------------------------------
#
# Exit immediately if a command exits with a non-zero status.
#
set -e
#
# Firmware name
#
FW=RepRapFirmware
LIB=${FW}/Libraries
BUILD=${FW}/Build
RELEASE=${FW}/Release
#
# Arduino version to use
#
ARDUINO=./arduino-1.5.4
ARDUINO_VERSION=154
#
# Is the Arduino folder valid?
#
if [ ! -d ${ARDUINO} ]; then
    #
    # No? Then we need to get it!
    # Do we need 32 or 64 bits?
    if [ $(uname -m) == x86_64 ]
        then ARCHIVE=${ARDUINO}-linux64.tgz
        else ARCHIVE=${ARDUINO}-linux32.tgz
    fi
    #
    # Do we have that file cached?
    if [ ! -f ${ARCHIVE} ]; then
        #
        # No? Then download a copy from arduino.cc
        wget http://downloads.arduino.cc/${ARCHIVE}
    fi
    #
    # Extract the file.
    tar -xvzf${ARCHIVE}
fi
#
# Is there a firmware?
#
if [ ! -d ${FW} ]; then
    #
    # No? Ask the user what version to download.
    #
    while true; do
        echo "Which firmware version do you want to use?"
        echo ""
        echo "[R] = RepRapPro original"
        echo "[D] = dc42's excellent fork"
        echo ""
        read -p "Please answer R or D: " input
        case $input in
            [Rr]* ) FW_REPO=git://github.com/RepRapPro/${FW}; break;;
            [Dd]* ) FW_REPO=git://github.com/dc42/${FW}; break;;
            * ) echo "Please answer R or D.";;
        esac
    done
    #
    # And download it from the repository.
    #
    git clone -b duet ${FW_REPO} ${FW}
fi
#
# Apply DC42's Arduino core patches.
#
if [ -d ${FW}/ArduinoCorePatches ]; then
    #
    # Always overwrite patched files because of git pull updates.
    #
    cp -r ${FW}/ArduinoCorePatches/sam ${ARDUINO}/hardware/arduino
fi
#
# Do we have the library?
#
if [ ! -d ${LIB} ]; then
    #
    # The RRP version does not include jmgiacalone's library.
    #
    git clone git://github.com/jmgiacalone/Arduino-libraries ${LIB}
fi
#
# Platform defines that I have copied from the Eclipse output window...
#
PLATFORM="-mcpu=cortex-m3 -DF_CPU=84000000L -DARDUINO=${ARDUINO_VERSION} -D__SAM3X8E__ -mthumb"
#
# USB defines that I have copied from the Eclipse output window...
#
USB_OPT="-DUSB_PID=0x003e -DUSB_VID=0x2341 -DUSBCON"
#
# Compiler options that I have copied from the Eclipse output window...
#
GCC_OPT="-c -g -O3 -w -ffunction-sections -fdata-sections -nostdlib --param max-inline-insns-single=500 -Dprintf=iprintf -MMD -MP"
GPP_OPT="-c -g -O3 -w -ffunction-sections -fdata-sections -nostdlib --param max-inline-insns-single=500 -Dprintf=iprintf -MMD -MP -fno-rtti -fno-exceptions -x c++"
COM_OPT=(
    -Os
    -mcpu=cortex-m3
    "-T${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x/linker_scripts/gcc/flash.ld"
    "-Wl,-Map,${BUILD}/RepRapFirmware.map"
    "-L${BUILD}"
    -lm
    -lgcc
    -mthumb
    -Wl,--cref
    -Wl,--check-sections
    -Wl,--gc-sections
    -Wl,--entry=Reset_Handler
    -Wl,--unresolved-symbols=report-all
    -Wl,--warn-common
    -Wl,--warn-section-align
    -Wl,--warn-unresolved-symbols
    -Wl,--start-group
    ${BUILD}/*.o
    ${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x/libsam_sam3x8e_gcc_rel.a
    -Wl,--end-group
)
#
# Location of the ARM compiler.
#
GCC_ARM_DIR=${ARDUINO}/hardware/tools/g++_arm_none_eabi
#
# Cross compiler binary locations.
#
AR=${GCC_ARM_DIR}/bin/arm-none-eabi-ar
GCC=${GCC_ARM_DIR}/bin/arm-none-eabi-gcc
GPP=${GCC_ARM_DIR}/bin/arm-none-eabi-g++
SIZE=${GCC_ARM_DIR}/bin/arm-none-eabi-size
COPY=${GCC_ARM_DIR}/bin/arm-none-eabi-objcopy
#
# Show commands and their arguments as they are executed.
#
set -x
#
# Make clean.
#
rm -rf ${BUILD}
rm -rf ${RELEASE}
mkdir -p ${BUILD}
mkdir -p ${RELEASE}
#
# Folders to include.
#
INC=(
    -I"${FW}/Flash"
    -I"${FW}/Libraries/EMAC"
    -I"${FW}/Libraries/Lwip"
    -I"${FW}/Libraries/MCP4461"
    -I"${FW}/Libraries/SamNonDuePin"
    -I"${FW}/Libraries/SD_HSMCI"
    -I"${FW}/Libraries/SD_HSMCI/utility"
    -I"${FW}/network"
    -I"${ARDUINO}/hardware/arduino/sam/cores/arduino"
    -I"${ARDUINO}/hardware/arduino/sam/variants/arduino_due_x"
    -I"${ARDUINO}/hardware/arduino/sam/system/libsam"
    -I"${ARDUINO}/hardware/arduino/sam/system/libsam/include"
    -I"${ARDUINO}/hardware/arduino/sam/system/CMSIS/Device/ATMEL/"
    -I"${ARDUINO}/hardware/arduino/sam/system/CMSIS/CMSIS/Include/"
    -I"${ARDUINO}/hardware/arduino/sam/libraries/Wire"
)
#
# Find all the .c files and compile them.
#
for file in $(find ${FW} ${ARDUINO}/hardware/arduino/sam/cores -type f -name "*.c"); do
    D=${BUILD}/$(basename $file).d
    O=${BUILD}/$(basename $file).o
    ${GCC} ${GCC_OPT} ${PLATFORM} ${USB_OPT} ${INC[@]} ${file} -MF${D} -MT${D} -o${O}
done
#
# Find all the .cpp files and compile them.
#
for file in $(find ${FW} ${ARDUINO}/hardware/arduino/sam -type f -name "*.cpp"); do
    D=${BUILD}/$(basename $file).d
    O=${BUILD}/$(basename $file).o
    ${GPP} ${GPP_OPT} ${PLATFORM} ${USB_OPT} ${INC[@]} ${file} -MF${D} -MT${D} -o${O}
done
#
# Combine the objects into an executable file.
#
${GPP} ${COM_OPT[@]} -o ${BUILD}/RepRapFirmware.elf
#
# Convert the ELF file to the firmware binary.
#
${COPY} -O binary ${BUILD}/RepRapFirmware.elf ${RELEASE}/RepRapFirmware.bin
#
# Output the details of the ELF binary.
#
${SIZE} -A ${BUILD}/RepRapFirmware.elf
#
# Show the output file name.
#
echo Created ${RELEASE}/RepRapFirmware.bin

