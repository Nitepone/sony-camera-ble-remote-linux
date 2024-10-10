#!/bin/bash
#
# Bluetooth remote for Sony Cameras
# Requires bluetoothctl and dialog
#
# author: Luna Hart <luna@night.horse>
#
# How to setup:
#   1. Open the Bluetooth Pairing Menu on the Camera
#   2. `bluetoothctl trust [MAC]`
#   3. `bluetoothctl pair [Camera MAC]`
#   4. Approve the pairing request on the Camera
#   5. **Reboot your system**
#   6. Run this script!
#     - (If you have multiple cameras, set the desired camera mac in
#        the SONY_CAMERA_MAC env variable)
#
# FAQs:
#   Q: "Why do I have to reboot in step 5?"
#   A: "I don't know. The GATT client doesn't seem to see the camera control
#       characteristic as writable until you reboot. I've tried powering the
#       the radio on and off. I've tried restarting bluetooth.service.
#       Please tell me if you find a better solution, send me an email."

declare -a tui_buttons=(
    "Shutter"
    "Half Shutter"
    "Record"
    "AF-ON"
    "C1"
)

declare -a tui_buttons_cmd_seqs=(
    "0 1" # Shutter: press then release
    "2 3" # Half Shutter: press then release
    "4 5" # Record: press then release
    "6 7" # AF-ON: press then release
    "8 9" # C1: press then release
)

target_mac=""
target_name=""


declare -a sony_ble_cmd_values=(
    "0x01 0x09"  # shutter-press
    "0x01 0x08"  # shutter-release
    "0x01 0x07"  # shutter-half-press
    "0x01 0x08"  # shutter-half-release
    "0x01 0x0E"  # record-press
    "0x01 0x0F"  # record-release
    "0x01 0x14"  # af-on-press
    "0x01 0x15"  # af-on-release
    "0x01 0x20"  # custom-1-press
    "0x01 0x21"  # custom-1-release
# untested..
#    "0x02 0x44 0x00"  # optical zoom tele
#    "0x02 0x45 0x10"  # digital zoom tele
#    "0x02 0x46 0x00"  # optical zoom wide
#    "0x02 0x47 0x10"  # digital zoom wide
#    "0x02 0x6a 0x00"  # Zoom In??
#    "0x02 0x6b 0x00"  # Focus In
#    "0x02 0x6c 0x00"  # Zoom Out?
#    "0x02 0x6d 0x00"  # Focus Out
)

# shellcheck disable=SC2034
declare -a sony_ble_cmd_names=(
    "Shutter Press"  # shutter-press
    "Shutter Release"  # shutter-release
    "Shutter Half Press"  # shutter-half-press
    "Shutter Half Release"  # shutter-half-release
    "Record Press"  # record-press
    "Record Release"  # record-release
    "AF-ON Press"  # af-on-press
    "AF-ON release"  # af-on-release
    "C1 press"  # custom-1-press
    "C1 release"  # custom-1-release
)

declare -r sony_ble_gatt_cmdchar_uuid="0000ff01-0000-1000-8000-00805f9b34fb"

function sony_is_connected {
    local device_string
    device_string="$(bluetoothctl devices Connected | grep "${target_mac}")"
    [[ -n ${device_string} ]]
}

function sony_connect {
    if ! sony_is_connected ; then
        bluetoothctl connect "${target_mac}" > /dev/null
        sleep 3
    fi
    if ! sony_is_connected ; then
        echo "Error connecting to camera!!" >&2
        return 1
    fi
    return 0
}

function sony_send_cmd {
    bluetoothctl > /dev/null << EOF
        gatt.select-attribute ${sony_ble_gatt_cmdchar_uuid}
        gatt.write '${1}'
EOF
}

function sony_send_cmd_seq {
    local cur_cmd
    if ! sony_connect; then
        return $?
    fi
    for cur_cmd in ${1}; do
        sony_send_cmd "${sony_ble_cmd_values[$cur_cmd]}"
        sleep .2
    done
}

function sony_take_photo {
    sony_send_cmd_seq "0 1"
}

function sony_disconnect {
    bluetoothctl disconnect "${target_mac}" > /dev/null
}


function tui_draw_controller {
    local d_ret
    local d_out
    local d_input_arr

    local num_cmds
    local cur_cmd
    local btn_idx

    d_input_arr=()
    num_cmds=${#tui_buttons[@]}
    for ((btn_idx = 0; btn_idx < num_cmds; btn_idx++)) ; do
        d_input_arr+=("$((btn_idx+1))")  # Increment by 1 for UX
        d_input_arr+=("${tui_buttons[$btn_idx]}")
    done

    exec 3>&1;
    d_out=$(dialog \
        --backtitle "Luna's Remote TUI" \
        --no-lines \
        --colors \
        --default-item "$tui_last_idx" \
        --cancel-label "Quit" \
        --ok-label "Send" \
        --menu "\ZbSony BLE Remote\n\Z5$target_name\n$target_mac\Zn" 15 31 20 "${d_input_arr[@]}" 2>&1 1>&3)
    d_ret=$?
    exec 3>&-;
    btn_idx=$((d_out - 1)) # Undo the increment by 1
    tui_last_idx=$d_out

    case $d_ret in
        0) # toggle button
            sony_send_cmd_seq "${tui_buttons_cmd_seqs[$btn_idx]}" &
            ;;
        1 | 255) # quit button or ctrl+c (1) || escape (255)
            sony_disconnect
            exit
            ;;
        default) # unknown
            echo "Closing due to unhandled dialog return $d_ret"
            exit
            ;;
    esac
}

if [[ -z "$SONY_CAMERA_MAC" ]] && [[ -z "$target_mac" ]]; then
    # No env variable? Let's hit the first paired (sony) device!
    target_mac="$(bluetoothctl devices | grep 'DC:FE:23' | head -1 | cut -d ' ' -f 2)"
fi
target_name="$(bluetoothctl devices | grep "$target_mac" | head -1 | cut -d ' ' -f 3)"

if [[ -z $target_mac ]]; then
    echo "Failed to find a camera!" >&2
    echo "Check bluetoothctl devices and set the SONY_CAMERA_MAC env variable." >&2
    echo "Ensure you have paired your device first!" >&2
    exit 1
fi

sony_connect &
while true; do
    tui_draw_controller
done
sony_disconnect
