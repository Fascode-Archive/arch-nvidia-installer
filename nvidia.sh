#!/usr/bin/env bash
#
# Yamada Hayao
# Twitter: @Hayao0819
# Email  : hayao@fascode.net
#
# (c) 2019-2021 Fascode Network.
#
# Alter Linux NVIDIA Installer
#
# This script sets up the NVIDIA driver on your Alter Linux
#
#================================================================
#
#         DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
#                     Version 2, December 2004 
#
#  Copyright (C) 2004 Sam Hocevar <sam@hocevar.net> 
#
#  Everyone is permitted to copy and distribute verbatim or modified 
#  copies of this license document, and changing it is allowed as long 
#  as the name is changed. 
#
#             DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE 
#    TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION 
#
#   0. You just DO WHAT THE FUCK YOU WANT TO.
#
#================================================================
#
# 参考
# https://wiki.archlinux.jp/index.php/NVIDIA]
# https://wiki.archlinux.org/title/NVIDIA/Troubleshooting
# https://wiki.archlinux.jp/index.php/Nouveau


#-- 設定 --#
mkinitcpio_conf="/etc/mkinitcpio.conf"
driver_packages=(
    "lib32-nvidia-utils"
    "lib32-opencl-nvidia"
#    "nvidia-dkms"
    "nvidia-utils"
    "opencl-nvidia"
)
driver_aur=()
debug=false
nocolor=false
grub=false
mkinitcpio=false
reinstall=false

#-- ハヤオの共通シェル関数 --#
# text [-b/-c color/-g color/-f/-l/]
# -b: 太字, -f: 点滅, -l: 下線, -n: リセット, 
text() {
    local OPTIND OPTARG _arg _textcolor _decotypes="" _bgcolor
    while getopts "c:bflng:" _arg; do
        case "${_arg}" in
            c | g)
                case "${OPTARG}" in
                    "black"  ) [[ "${_arg}" = "c" ]] && _textcolor="30" || _bgcolor="40";;
                    "red"    ) [[ "${_arg}" = "c" ]] && _textcolor="31" || _bgcolor="41";;
                    "green"  ) [[ "${_arg}" = "c" ]] && _textcolor="32" || _bgcolor="42";;
                    "yellow" ) [[ "${_arg}" = "c" ]] && _textcolor="33" || _bgcolor="43";;
                    "blue"   ) [[ "${_arg}" = "c" ]] && _textcolor="34" || _bgcolor="44";;
                    "magenta") [[ "${_arg}" = "c" ]] && _textcolor="35" || _bgcolor="45";;
                    "cyan"   ) [[ "${_arg}" = "c" ]] && _textcolor="36" || _bgcolor="46";;
                    "white"  ) [[ "${_arg}" = "c" ]] && _textcolor="37" || _bgcolor="47";;
                    *        ) return 1                                                 ;;
                esac
                ;;
            b) _decotypes="${_decotypes};1" ;;
            f) _decotypes="${_decotypes};5" ;;
            l) _decotypes="${_decotypes};4" ;;
            n) _decotypes="${_decotypes};0" ;;
            *) msg_error "Wrong use of text function" ;;
        esac
    done
    shift "$((OPTIND - 1))"
    if [[ "${nocolor}" = true ]]; then
        echo -ne "${*}"
    else
        echo -ne "\e[$([[ -v _textcolor ]] && echo -n ";${_textcolor}"; [[ -v _decotypes ]] && echo -n "${_decotypes}"; [[ -v _bgcolor ]] && echo -n ";${_bgcolor}")m${*}\e[m"
    fi
    return 0
}

# _msg_common <Label>:<Label Color> <Text>
_msg_common(){
    echo "$(text -c "$(echo "${1}" | cut -d ":" -f 2)" "$(echo "${1}" | cut -d ":" -f 1)"): ${2}" >&2
    return 0
}

# _msg_<type> <text>
_msg_info()  { _msg_common  "  Info:green"  "${1}"; }
_msg_warn()  { _msg_common  "  Warn:yellow" "${1}"; }
_msg_error() { 
    _msg_common  " Error:red"    "${1}"
    [[ -n "${2-""}" ]] && exit "${2}" || return 0
}
_msg_debug() {
    [[ "${debug}" = true ]] && _msg_common " Debug:magenta" "${1}"
    return 0
}

# 数値チェック
check_int(){ printf "%s" "${1}" | grep -qE "^[0-9]+$"; }

# 質問を行う関数
# Returns only the selected result to standard output
# ask_question -d <デフォルト値> -p <質問文> <選択肢1> <選択肢2> ...
ask_question(){
    local arg OPTARG OPTIND _default="" _choice_list _count _choice _question
    while getopts "d:p:" arg; do
        case "${arg}" in
            d) _default="${OPTARG}" ;;
            p) _question="${OPTARG}" ;;
            *) exit 1 ;;
        esac
    done
    shift "$((OPTIND - 1))"
    _choice_list=("${@}")
    _digit="${##}"

    # 選択肢に関するエラー
    if (( ${#_choice_list[@]} < 0 )); then
        msg_error "An exception error has occurred."
        exit 1
    fi

    # 選択肢が1つしか無いならばそのまま値を返す
    if (( ${#_choice_list[@]} <= 1 )); then
        echo "${_choice_list[*]}"
        return 0
    fi

    if [[ -v _question ]] && [[ ! "${_question}" = "" ]]; then
        echo -e "${_question}" >&2
    fi

    for (( _count=1; _count<=${#_choice_list[@]}; _count++)); do
        _choice="${_choice_list[$(( _count - 1 ))]}"
        if [[ ! "${_default}" = "" ]] && [[ "${_choice}" = "${_default}" ]]; then
            printf " * %${_digit}d: ${_choice}\n" "${_count}" >&2
        else
            printf "   %${_digit}d: ${_choice}\n" "${_count}" >&2
        fi
        unset _choice
    done
    echo -n "(1 ~ ${#_choice_list[@]}) > " >&2
    read -r _input

    # 回答を解析
    if check_int "${_input}"; then
        # 数字が入力された
        if (( 1 <= _input)) && (( _input <= ${#_choice_list[@]} )); then
            _choice="${_choice_list[$(( _input - 1 ))]}"
        else
            return 1
        fi
    else
        # 文字が入力された
        if printf "%s\n" "${_choice_list[@]}" | grep -x "${_input}" 1>/dev/null 2>&1; then
            _choice="${_input}"
        else
            return 1
        fi
    fi
    echo "${_choice}"
    return 0
}

# _grub_add_kernel_param <kernel param>
_grub_add_kernel_param(){
    local _grub_param
    [[ -z "${1-""}" ]] && return 1
    [[ "${grub}" = false ]] && return 0
    IFS=" " read -r -a _grub_param < <(eval "$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)"; echo "${GRUB_CMDLINE_LINUX_DEFAULT}")
    _msg_info "Currnet kernel param: ${_grub_param[*]}"
    { printf "%s\n" "${_grub_param[@]}" | grep -qx "${1}";} && { _msg_info "Parameter ${1} already exists"; return 0; }
    _msg_info "New kernel param: ${_grub_param[*]} ${1}"
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"${_grub_param[*]}\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${_grub_param[*]} ${1}\"|g" "/etc/default/grub"
}

# _grub_remove_kernel_param <kernel param>
_grub_remove_kernel_param(){
    local _grub_param_b _grub_param_a
    [[ -z "${1-""}" ]] && return 1
    [[ "${grub}" = false ]] && return 0
    IFS=" " read -r -a _grub_param_b < <(eval "$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub)"; echo "${GRUB_CMDLINE_LINUX_DEFAULT}")
    _msg_info "Currnet kernel param: ${_grub_param_b[*]}"
    { printf "%s\n" "${_grub_param_b[@]}" | grep -qx "${1}"; } || { _msg_info "Parameter ${1} not included"; return 0; }
    readarray -t _grub_param_a < <(printf "%s\n" "${_grub_param_b[@]}" | grep -xv "${1}")
    _msg_info "New kernel param: ${_grub_param_a[*]}"
    sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"${_grub_param_b[*]}\"|GRUB_CMDLINE_LINUX_DEFAULT=\"${_grub_param_a[*]}\"|g" "/etc/default/grub"
}

_mkinitcpio_add_modules(){
    local _module
    [[ -z "${1-""}" ]] && return 1
    [[ "${mkinitcpio}" = false ]] && return 0
    readarray -t _module < <(eval "$(grep "^MODULES=" /etc/mkinitcpio.conf)";printf "%s\n" "${MODULES[@]}")
    _msg_info "Currnet modules list: ${_module[*]}"
    { printf "%s\n" "${_module[@]}" | grep -qx "${1}";} && { _msg_info "Module ${1} already exists"; return 0; }
    _msg_info "New modules list: ${_module[*]} ${1}"
    sudo sed -i "s|^MODULES=(${_module[*]})|MODULES=(${_module[*]} ${1})|g" "/etc/mkinitcpio.conf"
}

_mkinitcpio_remove_modules(){
    local _module
    [[ -z "${1-""}" ]] && return 1
    [[ "${mkinitcpio}" = false ]] && return 0
    readarray -t _module_b < <(eval "$(grep "^MODULES=" /etc/mkinitcpio.conf)";printf "%s\n" "${MODULES[@]}")
    _msg_info "Currnet modules list: ${_module_b[*]}"
    { printf "%s\n" "${_module_b[@]}" | grep -qx "${1}"; } || { _msg_info "Module ${1} not included"; return 0; }
    readarray -t _module_a < <(printf "%s\n" "${_module_b[@]}" | grep -xv "${1}")
    _msg_info "New modules list: ${_module_a[*]}"
    sudo sed -i "s|^MODULES=(${_module_b[*]})|MODULES=(${_module_a[*]})|g" "/etc/mkinitcpio.conf"
}

#-- 異常終了 --#
trap 'echo; exit "${?}"' 1 2 3 15

#-- 処理開始 --#
_confirm(){
    #(( UID == 0 )) || _msg_error "Please run the script as root" 1 # Rootチェック

    _msg_info "Do you want to install NVIDIA Driver ?"
    [[ "$(ask_question -d "No" "Yes" "No")" = "Yes" ]] || exit 0

    trap 'exit ${?}' 1 2 3 15
}

_environment_check(){
    _msg_info "Checking your OS ..."
    (
        # shellcheck disable=SC1091
        source "/etc/os-release" 2> /dev/null || _msg_error "Failed to check distrribution" 1
        { [[ "${ID}" != "arch" ]] && [[ "${NAME}" != "Alter Linux" ]] && [[ "${NAME}" != "Arch Linux" ]] && [[ "${ID_LINE}" != "arch" ]];} || { [[ ! -f "${mkinitcpio_conf}" ]] && ! type mkinitcpio 1> /dev/null 2>&1 ;} && _msg_error "You cannnot run the script without Arch Linux" 1
        _msg_info "Your distro is ${NAME}"
    )

    # Env check
    { pacman -Qq grub > /dev/null || [[ -f "/boot/grub/grub.cfg" ]] ;} && grub=true && _msg_info "Found Grub."
    { pacman -Qq mkinitcpio > /dev/null || [[ -f "/etc/mkinitcpio.conf" ]] ;} && mkinitcpio=true && _msg_info "Found mkinitcpio."
    
    # Update database
    _msg_info "Updating pacman database"
    sudo pacman -Sy
    return 0

    # Driver installed
    if lsmod | cut -d " " -f 1 | grep -q nvidia; then
        _msg_info "Nvidia driver has been installed. Do you want to re-install it?"
        [[ "$(ask_question -d "No" "Yes" "No")" = "No" ]] && exit 0
        reinstall=true
        for _pkg in "nvidia" "nvidia-lts" "nvidia-dkms" "nvidia-390xx-dkms"; do
            pacman -Qq "${_pkg}" | grep -qx "${_pkg}" && driver_packages+=("${_pkg}")
            _msg_info "The script will install ${_pkg}"
        done
    fi

}

_select_install_pkg(){
    [[ "${reinstall}" = true ]] && return 0
    _msg_info "Which NVIDIA GPU are you using?"
    case "$(ask_question "GeForce 630-900, 10-20 or newer" "GeForce 400/500/600 2010-2011" "More older GPU" "I'm not using NVIDIA GPU." )" in
        "GeForce 630-900, 10-20 or newer")
            _msg_info "Your GPU is officialy supported"
            _msg_info "Which kernel are you using"
            case $(ask_question -d "$(basename "$(tr " " "\n" < "/proc/cmdline" | grep "^BOOT_IMAGE" | cut -d "=" -f 2)" | sed "s|^vmlinuz-||g")" "linux" "linux-lts" "linux-zen" "Other kernel") in
                "linux")
                    _msg_info "The script will install nvidia"
                    driver_packages+=("nvidia")
                    ;;
                "linux-lts")
                    _msg_info "The script will install nvidia-lts"
                    driver_packages+=("nvidia-lts")
                    ;;
                "Other kernel" | "linux-zen")
                    _msg_info "The script will install nvidia-dkms"
                    driver_packages+=("nvidia-dkms")
                    ;;
                *)
                    _msg_warn "Unexpected kernel has been selected."
                    _msg_warn "Install dkms driver"
                    _msg_info "The script will install nvidia-dkms"
                    driver_packages+=("nvidia-dkms")
                    ;;
            esac
            ;;
        "GeForce 400/500/600 2010-2011")
            _msg_info "Your GPU is old, so you should install driver from AUR"
            ! type yay > /dev/null 2>&1 && _msg_error "You should install yay" 1
            driver_aur+=("nvidia-390xx-dkms")
            ;;
        "More older GPU")
            _msg_error "This script does not support older GPUs." 1
            ;;
        "I'm not using NVIDIA GPU.")
            _msg_error "This script does not support non-NVIDIA GPUs." 1
            ;;
    esac
}

_install_driver(){
    local pacman_args=("-S")
    if (( "${#driver_packages[@]}" != 0 )); then
        _msg_info "Installing NVIDIA driver ..."
        [[ "${reinstall}" = false ]] && pacman_args+=("--needed")
        sudo pacman -S "${pacman_args[@]}" "${driver_packages[@]}"
    else
        _msg_warn "There are no packages to install from the repository."
    fi

    if (( "${#driver_aur[@]}" != 0 )); then
        _msg_info "Install driver from AUR ..."
        yay -S --needed "${driver_aur[@]}"
    else
        _msg_warn "There are no packages to install from AUR."
    fi
    return 0
}

_install_microcode(){
    pacman -Qq intel-ucode 1> /dev/null 2>&1 && sudo pacman -Sy --needed intel-ucode
}

_setup_drm_kms(){
    local _m
    _grub_add_kernel_param "nvidia-drm.modeset=1"
    for _m in "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm"; do
        _mkinitcpio_add_modules "${_m}"
    done
}

_fix_kernel_module(){
    # viafb
    _msg_info "Checking viafb module ..."
    if lsmod | cut -d " " -f 1 | grep -xq "viafb"; then
        _msg_info "Found viafb"
        _msg_info "Added viafb module to black list ..."
        if grep -q "^install viafb /usr/bin/false"; then
            _msg_error "viafb has been added to black list"
        else
            echo "install viafb /usr/bin/false" >> "/etc/modprobe.d/blacklist.conf"
        fi
    fi
    return 0
}

_finish(){
    _msg_info "The script ran all the commands successfully."
    return 0
}

_run(){
    _confirm
    _environment_check
    _select_install_pkg
    _install_driver
    _install_microcode
    _setup_drm_kms
    _fix_kernel_module
    _finish
    return 0
}

_run

exit 0
