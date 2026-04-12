#!/bin/bash

# ColorOS_port project

# For A-only and V/A-B (not tested) Devices

# Based on Android 14 

# Test Base ROM: OnePlus 8T (ColorOS_14.0.0.600)

# Test Port ROM: OnePlus 12 (ColorOS_14.0.0.810), OnePlus ACE3V(ColorOS_14.0.1.621) Realme GT Neo5 240W(RMX3708_14.0.0.800)

build_user="Bruce Teng,Co-Create team"
build_host=$(hostname)

# 底包和移植包为外部参数传入
baserom="$1"
portrom="$2"
portrom2="$3"
portparts="$4"
work_dir=$(pwd)
tools_dir=${work_dir}/bin/$(uname)/$(uname -m)
export PATH=$(pwd)/bin/$(uname)/$(uname -m)/:$(pwd)/otatools/bin/:$PATH

# Import functions
source functions.sh

check unzip aria2c 7z zip java python3 zstd bc xmlstarlet

# 可在 bin/port_config 中更改
port_partition=$(grep "partition_to_port" bin/port_config |cut -d '=' -f 2)
super_list=$(grep "possible_super_list" bin/port_config |cut -d '=' -f 2)
repackext4=$(grep "repack_with_ext4" bin/port_config |cut -d '=' -f 2)
super_extended=$(grep "super_extended" bin/port_config |cut -d '=' -f 2)
pack_with_dsu=$(grep "pack_with_dsu" bin/port_config | cut -d '=' -f 2)
pack_method=$(grep "pack_method" bin/port_config | cut -d '=' -f 2)
ddr_type=$(grep "ddr_type" bin/port_config | cut -d '=' -f 2)
reusabe_partition_list=$(grep "reusabe_partition_list" bin/port_config | cut -d '=' -f 2)
if [[ ${repackext4} == true ]]; then
    pack_type=EXT
else
    pack_type=EROFS
fi
# 检查为本地包还是链接
if [ ! -f "${baserom}" ] && [ "$(echo $baserom |grep http)" != "" ];then
    blue "底包为一个链接，正在尝试下载" "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${baserom}
    baserom=$(basename ${baserom} | sed 's/\?t.*//')
    if [ ! -f "${baserom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${baserom}" ];then
    green "底包: ${baserom}" "BASEROM: ${baserom}"
else
    error "底包参数错误" "BASEROM: Invalid parameter"
    exit
fi

if [ ! -f "${portrom}" ] && [ "$(echo ${portrom} |grep http)" != "" ];then
    blue "移植包为一个链接，正在尝试下载"  "Download link detected, start downloding.."
    aria2c --max-download-limit=1024M --file-allocation=none -s10 -x10 -j10 ${portrom}
    portrom=$(basename ${portrom} | sed 's/\?t.*//')
    if [ ! -f "${portrom}" ];then
        error "下载错误" "Download error!"
    fi
elif [ -f "${portrom}" ];then
    green "移植包: ${portrom}" "PORTROM: ${portrom}"
else
    error "移植包参数错误" "PORTROM: Invalid parameter"
    exit
fi

if [ "$(echo $baserom |grep ColorOS_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="op8t"
fi
if [ -f "${baserom}" ];then
    green "底包: ${baserom}" "BASEROM: ${baserom}"
else
    error "底包参数错误" "BASEROM: Invalid parameter"
    exit
fi

if [ -f "${portrom}" ];then
    green "移植包: ${portrom}" "PORTROM: ${portrom}"
else
    error "移植包参数错误" "PORTROM: Invalid parameter"
    exit
fi

if [ "$(echo $baserom |grep ColorOS_)" != "" ];then
    device_code=$(basename $baserom |cut -d '_' -f 2)
else
    device_code="op8t"
fi

blue "正在检测ROM底包" "Validating BASEROM.."

# 检测底包类型
if unzip -l "${baserom}" | grep -q "payload.bin"; then
    baserom_type="payload"
    oplus_hex_nv_id=$(unzip -p "${baserom}" META-INF/com/android/metadata 2>/dev/null | grep "oplus_hex_nv_id=" | cut -d= -f2)
elif unzip -l "${baserom}" | grep -Eq "br$"; then
    baserom_type="br"
    oplus_hex_nv_id=$(unzip -p "${baserom}" META-INF/com/android/metadata 2>/dev/null | grep "oplus_hex_nv_id=" | cut -d= -f2)
elif unzip -l "${baserom}" | grep -Eq "\.img$"; then
    baserom_type="img"
else
    error "底包中未发现 payload.bin、br 或 img 文件，请使用官方ROM包后重试" \
          "payload.bin / *.br / *.img not found, please use official OTA or fastboot package."
    exit 1
fi

green "检测到底包类型: ${baserom_type}" "Detected base package type: ${baserom_type}"


blue "开始检测ROM移植包" "Validating PORTROM.."

# 检测移植包类型
if unzip -l "${portrom}" | grep -q "payload.bin"; then
    portrom_type="payload"
elif unzip -l "${portrom}" | grep -Eq "\.img$"; then
    portrom_type="img"
else
    error "目标移植包中未发现 payload.bin 或 img 文件，请使用包含 system.img 的官方ROM包作为移植包" \
          "payload.bin or *.img not found, please use an official ROM package containing system.img as PORTROM."
    exit 1
fi

# 提取版本信息（仅当有 metadata 时）
if unzip -l "${portrom}" | grep -q "META-INF/com/android/metadata"; then
    version_name=$(unzip -p "${portrom}" META-INF/com/android/metadata 2>/dev/null | grep "version_name=" | cut -d= -f2)
    ota_version=$(unzip -p "${portrom}" META-INF/com/android/metadata 2>/dev/null | grep "ota_version=" | cut -d= -f2)
else
    version_name="$(basename ${portrom%.*})"
    ota_version="V16.0.0"
fi

green "ROM初步检测通过，类型: ${portrom_type}" "ROM validation passed. Type: ${portrom_type}"
[[ -n "${version_name}" ]] && echo "版本名: ${version_name}"


if [[ -n $portrom2 ]];then
    mix_port=true
fi

if [[ -n $portparts ]];then
    mix_port_part=($portparts)
else
    mix_port_part=("my_stock" "my_region" "my_manifest" "my_product")
fi

if [[ $mix_port == true ]];then
    blue "混合移植包模式"
    blue "开始检测第二个移植包" "Validating PORTROM.."
    if unzip -l ${portrom2} | grep  -q "payload.bin"; then
        green "第二个ROM初步检测通过" "ROM validation passed."
        portrom2_type="payload"
	version_name2=$(unzip -p ${portrom2} META-INF/com/android/metadata | grep "version_name=" | cut -d = -f2)
    elif unzip -l "${portrom2}" | grep -Eq "\.img$"; then
        portrom2_type="img"
        version_name2="$(basename "${portrom2%.*}")"
    else
        error "目标移植包中未发现 payload.bin 或 img 文件，请使用包含 system.img 的官方ROM包作为移植包" \
          "payload.bin or *.img not found, please use an official ROM package containing system.img as PORTROM."
        exit 1
    fi
fi
green "ROM初步检测通过" "ROM validation passed."

blue "正在清理文件" "Cleaning up.."

rm -rf app
rm -rf tmp
rm -rf config
rm -rf build/baserom/
rm -rf build/portrom/
find . -type d -name 'ColorOS_*' |xargs rm -rf

green "文件清理完毕" "Files cleaned up."
mkdir -p build/baserom/images/

mkdir -p build/portrom/images/

mkdir tmp 
export TMPDIR=$work_dir/tmp/
# ===== 提取底包 =====
if [[ ${baserom_type} == 'payload' ]]; then
    blue "正在提取底包 [payload.bin]" "Extracting files from BASEROM [payload.bin]"   
    payload-dumper --out build/baserom/images/ "${baserom}"
    green "底包 [payload.bin] 提取完毕" "[payload.bin] extracted."

elif [[ ${baserom_type} == 'br' ]]; then
    blue "正在提取底包 [new.dat.br]" "Extracting files from BASEROM [*.new.dat.br]"
    unzip -q "${baserom}" -d build/baserom || \
        error "解压底包 [new.dat.br]时出错" "Extracting [new.dat.br] error"
    green "底包 [new.dat.br] 解压完毕" "[new.dat.br] extracted."

    blue "开始分解底包 [new.dat.br]" "Unpacking BASEROM [new.dat.br]"
    # 修复带数字的文件名问题
    for file in build/baserom/*; do
        filename=$(basename -- "$file")
        extension="${filename##*.}"
        name="${filename%.*}"

        if [[ $name =~ [0-9] ]]; then
            new_name=$(echo "$name" | sed 's/[0-9]\+\(\.[^0-9]\+\)/\1/g' | sed 's/\.\./\./g')
            mv -fv "$file" "build/baserom/${new_name}.${extension}"
        fi
    done

    # 转换为 .img
    for i in ${super_list}; do 
        if [[ -f build/baserom/${i}.new.dat.br ]]; then
            ${tools_dir}/brotli -d build/baserom/${i}.new.dat.br >/dev/null 2>&1
            python3 ${tools_dir}/sdat2img.py \
                build/baserom/${i}.transfer.list \
                build/baserom/${i}.new.dat \
                build/baserom/images/${i}.img >/dev/null 2>&1
            rm -rf build/baserom/${i}.new.dat* build/baserom/${i}.transfer.list build/baserom/${i}.patch.*
        fi
    done
    green "底包 [new.dat.br] 分解完毕" "[new.dat.br] unpack complete."

elif [[ ${baserom_type} == 'img' ]]; then
    blue "检测到底包类型为 [img]" "Extracting BASEROM containing .img files"
    mkdir -p build/baserom/images/
    unzip -q "${baserom}" -d build/baserom/tmp/ || \
        error "解压底包时出错" "Extracting BASEROM error"
    # 移动所有 img 文件
    find build/baserom/tmp/ -type f -name "*.img" -exec mv -fv {} build/baserom/images/ \;
    rm -rf build/baserom/tmp/
    green "底包 [*.img] 提取完毕" "[*.img] extracted."
else
    error "未知底包类型: ${baserom_type}" "Unknown base package type: ${baserom_type}"
    exit 1
fi


# ===== 提取移植包 =====
if [[ -n ${version_name} ]] && [[ -d build/${version_name} ]]; then 
    blue "检测到已存在解压的移植包cache文件夹 ${version_name}，从中复制" \
         "Cached ${version_name} folder detected, copying..."
    IFS=',' read -ra PARTS <<< "$port_partition"
    for i in "${PARTS[@]}"; do
        cp -rfv "build/${version_name}/${i}.img" build/portrom/images/
    done

else
    mkdir -p build/${version_name}/ build/portrom/images/

    if [[ ${portrom_type} == 'payload' ]]; then
        blue "正在提取移植包 [payload.bin]" "Extracting PORTROM [payload.bin]"
        payload-dumper --partitions "${port_partition}" --out "build/${version_name}/" "${portrom}"
        cp -rfv build/${version_name}/*.img build/portrom/images/
        green "移植包 [payload.bin] 提取完毕" "[payload.bin] extracted."

    elif [[ ${portrom_type} == 'img' ]]; then
        blue "检测到移植包类型为 [img]" "Extracting PORTROM containing .img files"
        # 将逗号分隔的分区名转为数组
        IFS=',' read -ra PARTS <<< "$port_partition"

        # 构建解压参数
        declare -a unzip_targets=()
        for part in "${PARTS[@]}"; do
          unzip_targets+=("${part}.img" "${part}_a.img" "${part}_b.img")
        done

        blue "正在选择性解压移植包中的img文件" "Extracting specific img files from PORTROM"

        # 仅解压指定分区的img文件
        unzip -q "${portrom}" "${unzip_targets[@]}" -d "build/${version_name}/" || \
        error "解压指定 img 文件失败，请检查包中是否包含 ${port_partition}" \
          "Failed to extract specified img files from PORTROM."

         green "指定分区镜像解压完成" "Selected partitions extracted successfully."
        find "build/${version_name}/" -type f -name "*.img" -exec cp -fv {} build/portrom/images/ \;
        green "移植包 [*.img] 提取完毕" "[*.img] extracted."

    else
        error "未知移植包类型: ${portrom_type}" "Unknown port package type: ${portrom_type}"
        exit 1
    fi
fi

if [[ -n ${version_name2} ]] && [[ -d build/${version_name2} ]];then 
    blue "检测到已存在解压的第二个移植包cache文件夹${version_name2}，从中复制" "cached ${version_name2} folder detected, copying"
    #IFS=',' read -ra PARTS <<< "$port_partition"  # 用逗号分割为数组
    for i in "${mix_port_part[@]}"; do
        # if [[ -f build/${version_name}/${i}_patched.img ]];then
        #     skip_list2+=("$i")
        #     cp -rfv build/${version_name}/${i}_patched.img build/portrom/images/${i}.img
        #else 
            cp -rfv build/${version_name2}/${i}.img build/portrom/images/
        #fi
    done
elif [[ -n ${version_name2} ]];then
    if [[ ${portrom2_type} == 'payload' ]]; then
        blue "正在提取移植包 [payload.bin]" "Extracting files from PORTROM [payload.bin]"
        mkdir -p build/${version_name2}/
        payload-dumper --partitions ${port_partition} --out build/${version_name2}/ $portrom2
        for i in "${mix_port_part[@]}"; do
            cp -rfv build/${version_name2}/${i}.img build/portrom/images/
        done
    elif [[ ${portrom2_type} == 'img' ]]; then
        blue "检测到移植包2类型为 [img]" "Extracting PORTROM containing .img files"
        # 将逗号分隔的分区名转为数组
        IFS=',' read -ra PARTS <<< "$port_partition"

        # 构建解压参数
        declare -a unzip_targets=()
        for part in "${PARTS[@]}"; do
          unzip_targets+=("${part}.img" "${part}_a.img" "${part}_b.img")
        done

        blue "正在选择性解压移植包中的img文件" "Extracting specific img files from PORTROM"

        # 仅解压指定分区的img文件
        unzip -q "${portrom2}" "${unzip_targets[@]}" -d "build/${version_name2}/" || \
        error "解压指定 img 文件失败，请检查包中是否包含 ${port_partition}" \
          "Failed to extract specified img files from PORTROM."

         green "指定分区镜像解压完成" "Selected partitions extracted successfully."
        find "build/${version_name2}/" -type f -name "*.img" -exec cp -fv {} build/portrom/images/ \;
        green "移植包 [*.img] 提取完毕" "[*.img] extracted."
    fi
fi

if [[ -n ${version_name} ]] && [[ -n ${version_name2} ]];then
    app_patch_folder=${version_name2}
elif [[ -n ${version_name} ]];then
    app_patch_folder=${version_name}
fi

for part in system product system_ext my_product my_manifest;do
    extract_partition build/baserom/images/${part}.img build/baserom/images    
done

# Move those to portrom folder. We need to pack those imgs into final port rom
for image in vendor odm my_company my_preload system_dlkm vendor_dlkm my_engineering;do
    if [ -f build/baserom/images/${image}.img ];then
        mv -f build/baserom/images/${image}.img build/portrom/images/${image}.img

        # Extracting vendor at first, we need to determine which super parts to pack from Baserom fstab. 
        extract_partition build/portrom/images/${image}.img build/portrom/images/

    fi
done

if [ ! -d build/portrom/images/system_dlkm ];then
        super_list="system system_ext vendor product my_product odm my_engineering my_stock my_heytap my_carrier my_region my_bigball my_manifest my_company my_preload"
fi
# Extract the partitions list that need to pack into the super.img
#super_list=$(sed '/^#/d;/^\//d;/overlay/d;/^$/d;/\^loop/d' build/portrom/images/vendor/etc/fstab.qcom \
#                | awk '{ print $1}' | sort | uniq)

# 分解镜像
green "开始提取逻辑分区镜像" "Starting extract portrom partition from img"
for part in ${super_list};do
    # 检查是否在 skip_list1 或 skip_list2 中
#    if [[ " ${skip_list1[@]} " =~ " ${part} " ]] || [[ " ${skip_list2[@]} " =~ " ${part} " ]]; then
 #       yellow "跳过分区 [${part}]，已通过patched镜像复用" "Skip [${part}], already reused from patched image"
  #      continue
   # fi
    # Skip already extraced parts from BASEROM
    if [[ ! -d build/portrom/images/${part} ]]; then
        blue "提取 [${part}] 分区..." "Extracting [${part}]"

        (
        extract_partition "${work_dir}/build/portrom/images/${part}.img" "${work_dir}/build/portrom/images/" && \
        rm -rf "${work_dir}/build/baserom/images/${part}.img"
        ) &
    else
        yellow "跳过从PORTORM提取分区[${part}]" "Skip extracting [${part}] from PORTROM"
    fi
done
wait
rm -rf config

blue "正在获取ROM参数" "Fetching ROM build prop."

# 安卓版本
base_android_version=$(< build/baserom/images/system/system/build.prop grep "ro.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
port_android_version=$(< build/portrom/images/system/system/build.prop grep "ro.build.version.release" |awk 'NR==1' |cut -d '=' -f 2)
green "安卓版本: 底包为[Android ${base_android_version}], 移植包为 [Android ${port_android_version}]" "Android Version: BASEROM:[Android ${base_android_version}], PORTROM [Android ${port_android_version}]"

# SDK版本
base_android_sdk=$(< build/baserom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
port_android_sdk=$(< build/portrom/images/system/system/build.prop grep "ro.system.build.version.sdk" |awk 'NR==1' |cut -d '=' -f 2)
green "SDK 版本: 底包为 [SDK ${base_android_sdk}], 移植包为 [SDK ${port_android_sdk}]" "SDK Verson: BASEROM: [SDK ${base_android_sdk}], PORTROM: [SDK ${port_android_sdk}]"

# ROM版本
base_rom_version=$(<  build/baserom/images/my_manifest/build.prop grep "ro.build.display.ota" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 2-)
port_rom_version=$(<  build/portrom/images/my_manifest/build.prop grep "ro.build.display.ota" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 2-)
green "ROM 版本: 底包为 [${base_rom_version}], 移植包为 [${port_rom_version}]" "ROM Version: BASEROM: [${base_rom_version}], PORTROM: [${port_rom_version}] "

#ColorOS版本号获取

base_device_code=$(< build/baserom/images/my_manifest/build.prop grep "ro.oplus.version.my_manifest" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 1)
port_device_code=$(< build/portrom/images/my_manifest/build.prop grep "ro.oplus.version.my_manifest" | awk 'NR==1' | cut -d '=' -f 2 | cut -d "_" -f 1)

green "机型代号: 底包为 [${base_device_code}], 移植包为 [${port_device_code}]" "Device Code: BASEROM: [${base_device_code}], PORTROM: [${port_device_code}]"
# 代号
base_product_device=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.device" |awk 'NR==1' |cut -d '=' -f 2)
port_product_device=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.device" |awk 'NR==1' |cut -d '=' -f 2)
green "Product机型: 底包为 [${base_product_device}], 移植包为 [${port_product_device}]" "Product Device: BASEROM: [${base_product_device}], PORTROM: [${port_product_device}]"

base_product_name=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.name" |awk 'NR==1' |cut -d '=' -f 2)
port_product_name=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.name" |awk 'NR==1' |cut -d '=' -f 2)
green "Product名称: 底包为 [${base_product_name}], 移植包为 [${port_product_name}]" "Product Name: BASEROM: [${base_product_name}], PORTROM: [${port_product_name}]"

base_product_model=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.model" |awk 'NR==1' |cut -d '=' -f 2)
port_product_model=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.model" |awk 'NR==1' |cut -d '=' -f 2)
green "Product型号: 底包为 [${base_product_model}], 移植包为 [${port_product_model}]" "Product Model: BASEROM: [${base_product_model}], PORTROM: [${port_product_model}]"
if grep -q "ro.vendor.oplus.market.name" build/baserom/images/my_manifest/build.prop;then
    base_market_name=$(< build/baserom/images/my_manifest/build.prop grep "ro.vendor.oplus.market.name" |awk 'NR==1' |cut -d '=' -f 2)
else
    base_market_name=$(< build/portrom/images/odm/build.prop grep "ro.vendor.oplus.market.name" |awk 'NR==1' |cut -d '=' -f 2)
fi

if grep -q "ro.vendor.oplus.market.enname" build/baserom/images/my_manifest/build.prop;then
    base_market_enname=$(< build/baserom/images/my_manifest/build.prop grep "ro.vendor.oplus.market.enname" |awk 'NR==1' |cut -d '=' -f 2)
else
    base_market_enname=$(< build/portrom/images/odm/build.prop grep "ro.vendor.oplus.market.enname" |awk 'NR==1' |cut -d '=' -f 2)
fi

port_market_name=$(grep -r --include="*.prop"  --exclude-dir="odm" "ro.vendor.oplus.market.name" build/portrom/images/ | head -n 1 | awk "NR==1" | cut -d "=" -f2)

green "市场名称: 底包为 [${base_market_name}], 移植包为 [${port_market_name}]" "Market Name: BASEROM: [${base_market_name}], PORTROM: [${port_market_name}]"

base_my_product_type=$(< build/baserom/images/my_product/build.prop grep "ro.oplus.image.my_product.type" |awk 'NR==1' |cut -d '=' -f 2)
port_my_product_type=$(< build/portrom/images/my_product/build.prop grep "ro.oplus.image.my_product.type" |awk 'NR==1' |cut -d '=' -f 2)

green "my_product类型: 底包为 [${base_my_product_type}], 移植包为 [${port_my_product_type}]" "My_Product Type: BASEROM: [${base_my_product_type}], PORTROM: [${port_my_product_type}]"

target_display_id=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.display.id=" |awk 'NR==1' |cut -d '=' -f 2 | sed "s/$port_device_code/$base_device_code/g")

target_display_id_show=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.display.id.show" |awk 'NR==1' |cut -d '=' -f 2 | sed "s/$port_device_code/$base_device_code/g") 

base_vendor_brand=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.vendor.brand" |awk 'NR==1' |cut -d '=' -f 2)
port_vendor_brand=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.vendor.brand" |awk 'NR==1' |cut -d '=' -f 2)

port_ssi_brand=$(< build/portrom/images/system_ext/etc/build.prop grep "ro.oplus.image.system_ext.brand" |awk 'NR==1' |cut -d '=' -f 2)

base_product_first_api_level=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.first_api_level" |awk 'NR==1' |cut -d '=' -f 2)
port_product_first_api_level=$(< build/portrom/images/my_manifest/build.prop grep "ro.product.first_api_level" |awk 'NR==1' |cut -d '=' -f 2)

base_device_family=$(< build/baserom/images/my_product/build.prop grep "ro.build.device_family" |awk 'NR==1' |cut -d '=' -f 2)
target_device_family=$(< build/portrom/images/my_product/build.prop grep "ro.build.device_family" |awk 'NR==1' |cut -d '=' -f 2)

# Security Patch Date
portrom_version_security_patch=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.version.security_patch" |awk 'NR==1' |cut -d '=' -f 2 )
port_oplusrom_version=$(< build/portrom/images/my_product/build.prop grep "ro.build.version.oplusrom.confidential" |awk 'NR==1' |cut -d '=' -f 2 )

port_release_or_codename=$(< build/portrom/images/my_manifest/build.prop grep "ro.build.version.release_or_codename" |awk 'NR==1' |cut -d '=' -f 2)
    
#regionmark=$(< build/portrom/images/my_bigball/etc/region/build.prop grep "ro.vendor.oplus.regionmark" |awk 'NR==1' |cut -d '=' -f 2)
regionmark=$(find build/portrom/images/ -name build.prop -exec grep -m1 "ro.vendor.oplus.regionmark=" {} \; -quit | cut -d '=' -f2)

base_regionmark=$(find build/baserom/images/ -name build.prop -exec grep -m1 "ro.vendor.oplus.regionmark=" {} \; -quit | cut -d '=' -f2)
if [ -z "$base_regionmark" ]; then
  base_regionmark=$(find build/baserom/images/ -name build.prop -exec grep -m1 "ro.oplus.image.my_region.type=" {} \; -quit | cut -d '=' -f2 | cut -d '_' -f1)
fi

base_ab_partitions=$(< build/baserom/images/my_manifest/build.prop grep "ro.product.ab_ota_partitions" |awk 'NR==1' |cut -d '=' -f 2)

vendor_cpu_abilist32=$(< build/portrom/images/vendor/build.prop grep "ro.vendor.product.cpu.abilist32" |awk 'NR==1' |cut -d '=' -f 2 )

base_area=$(grep -r --include="*.prop" --exclude-dir="odm" "ro.oplus.image.system_ext.area" build/baserom/images/ | head -n1 | cut -d "=" -f2 | tr -d '\r')
base_brand=$(grep -r --include="*.prop" --exclude-dir="odm" "ro.oplus.image.system_ext.brand" build/baserom/images/ | head -n1 | cut -d "=" -f2 | tr -d '\r')

baseIsColorOSCN=false
baseIsOOS=false
baseIsRealmeUI=false
if [[ "$base_area" == "domestic" && "$base_brand" != "realme" ]]; then
    baseIsColorOSCN=true
elif [[ "base_brand" == "realme" ]];then
    baseIsRealmeUI=true
elif [[ "$base_area" == "gdpr" && "$base_brand" == "oneplus" ]]; then
    baseIsOOS=true
fi

port_area=$(grep -r --include="*.prop" --exclude-dir="odm" "ro.oplus.image.system_ext.area" build/portrom/images/ | head -n1 | cut -d "=" -f2 | tr -d '\r')
port_brand=$(grep -r --include="*.prop" --exclude-dir="odm" "ro.oplus.image.system_ext.brand" build/portrom/images/ | head -n1 | cut -d "=" -f2 | tr -d '\r')

portIsColorOSGlobal=false
portIsOOS=false
portIsColorOS=false
portIsRealmeUI=false

port_oplusrom_version=$(get_oplusrom_version)

if [[ "$port_brand" == "realme" ]];then
    portIsRealmeUI=true
fi

if [[ "$port_area" == "gdpr" && "$port_brand" != "oneplus" ]]; then
    portIsColorOSGlobal=true
elif [[ "$port_area" == "gdpr" && "$port_brand" == "oneplus" ]]; then
    portIsOOS=true
else
    portIsColorOS=true
fi


if grep -q "ro.build.ab_update=true" build/portrom/images/vendor/build.prop;  then
    is_ab_device=true
else
    is_ab_device=false

fi

if [[ ! -f build/portrom/images/system/system/bin/app_process32 && -n "$vendor_cpu_abilist32" ]]; then
    blue "64bit only protrom detected. convert vendor to 64bit-only  "
    sed -i "s/ro.vendor.product.cpu.abilist=.*/ro.vendor.product.cpu.abilist=arm64-v8a/g" build/portrom/images/vendor/build.prop
    sed -i "s/ro.vendor.product.cpu.abilist32=.*/ro.vendor.product.cpu.abilist32=/g" build/portrom/images/vendor/build.prop
    sed -i "s/ro.zygote=.*/ro.zygote=zygote64/g" build/portrom/images/vendor/default.prop
    #cp -rfv devices/32-libs/* build/portrom/images/
fi

if [[ -f devices/${base_product_device}/config ]];then
   source devices/${base_product_device}/config
fi
#rm -rf build/portrom/images/my_manifest
#cp -rf build/baserom/images/my_manifest build/portrom/images/
#cp -rf build/baserom/images/config/my_manifest_* build/portrom/images/config/
sed -i "s/ro.build.display.id=.*/ro.build.display.id=${target_display_id}/g" build/portrom/images/my_manifest/build.prop
sed -i "s/ro.product.first_api_level=.*/ro.product.first_api_level=${base_product_first_api_level}/g" build/portrom/images/my_manifest/build.prop


if  ! grep -q  "ro.build.display.id.show" build/portrom/images/my_manifest/build.prop ;then
    echo "ro.build.display.id.show=$target_display_id_show" >> build/portrom/images/my_manifest/build.prop
else
    sed -i "s/ro.build.display.id.show=.*/ro.build.display.id.show=${target_display_id_show}/g" build/portrom/images/my_manifest/build.prop
fi
sed -i '/ro.build.version.release=/d' build/portrom/images/my_manifest/build.prop
sed -i "s/ro.vendor.oplus.market.name=.*/ro.vendor.oplus.market.name=${base_market_name}/g" build/portrom/images/my_manifest/build.prop
sed -i "s/ro.vendor.oplus.market.enname=.*/ro.vendor.oplus.market.enname=${base_market_enname}/g" build/portrom/images/my_manifest/build.prop

sed -i "s/ro.product.ab_ota_partitions=.*/ro.product.ab_ota_partitions=${base_ab_partitions}/g" build/portrom/images/my_manifest/build.prop
    

sed -i '/ro.oplus.watermark.betaversiononly.enable=/d' build/portrom/images/my_manifest/build.prop

if [[ $base_android_version -le 14 ]];then
    BASE_PROP="build/baserom/images/my_manifest/build.prop"
    PORT_PROP="build/portrom/images/my_manifest/build.prop"

    KEYS="\.name= \.model= \.manufacturer= \.device= \.brand= \.my_product.type="

    for k in $KEYS; do
        grep "$k" "$BASE_PROP" | while IFS='=' read -r key value; do
            if [[ "$key" == "ro.product.vendor.brand" ]]; then
                # 特殊处理：强制写 OPPO
                sed -i "s|^$key=.*|$key=OPPO|" "$PORT_PROP" 
            elif grep -q "^$key=" "$PORT_PROP"; then
                sed -i "s|^$key=.*|$key=$value|" "$PORT_PROP"
            fi
        done
    done
fi
# OOS 16 mixed port
if [[ -n $vendor_cpu_abilist32 ]] ;then
    sed -i "/ro.zygote=zygote64/d" build/portrom/images/my_manifest/build.prop
fi
#其他机型可能没有default.prop
for prop_file in $(find build/portrom/images/vendor/ -name "*.prop"); do
    vndk_version=$(< "$prop_file" grep "ro.vndk.version" | awk "NR==1" | cut -d '=' -f 2)
    if [ -n "$vndk_version" ]; then
        yellow "ro.vndk.version为$vndk_version" "ro.vndk.version found in $prop_file: $vndk_version"
        break  
    fi
done
base_vndk=$(find build/baserom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")
port_vndk=$(find build/portrom/images/system_ext/apex -type f -name "com.android.vndk.v${vndk_version}.apex")

if [ ! -f "${port_vndk}" ]; then
    yellow "apex不存在，从原包复制" "target apex is missing, copying from baserom"
    cp -rf "${base_vndk}" "build/portrom/images/system_ext/apex/"
fi
for prop in $(find build/portrom/images -name "build.prop");do 
    sed -i "s/ro.build.version.security_patch=.*/ro.build.version.security_patch=${portrom_version_security_patch}/g" $prop
done


old_face_unlock_app=$(find build/baserom/images/my_product -name "OPFaceUnlock.apk")
if [[ -f build/${app_patch_folder}/patched/services.jar ]];then
    blue "复制已经处理过的services.jar"
    cp -rfv build/${app_patch_folder}/patched/services.jar build/portrom/images/system/system/framework/services.jar
elif [[ -f build/portrom/images/system/system/framework/services.jar ]];then 
    if [[ ! -d tmp ]];then
        mkdir -p tmp/
    fi

    mkdir -p tmp/services/
    cp -rf build/portrom/images/system/system/framework/services.jar tmp/services.jar
    framework_res=$(find build/portrom/images/ -type f -name "framework-res.apk")
    extra_args=""

    if [[ -f $framework_res ]];then
        extra_args="-framework $framework_res"
    fi

    java -jar bin/apktool/APKEditor.jar d -f -i tmp/services.jar -o tmp/services


    smalis=("ScanPackageUtils")
    methods=("--assertMinSignatureSchemeIsValid")

    for (( i=0; i<${#smalis[@]}; i++ )); do
        smali="${smalis[i]}"
        method="${methods[i]}"
        
        target_file=$(find tmp/services -type f -name "${smali}.smali")
        echo "smali is $smali"
        echo "target_file is $target_file"
        
        if [[ -f $target_file ]]; then
            for single_method in $method; do
                python3 bin/patchmethod.py $target_file $single_method && echo "${target_file} patched successfully"
            done
        fi
    done

    target_method='getMinimumSignatureSchemeVersionForTargetSdk' 
    old_smali_dir=""
    declare -a smali_dirs

    while read -r smali_file; do
        smali_dir=$(echo "$smali_file" | cut -d "/" -f 3)

        if [[ $smali_dir != $old_smali_dir ]]; then
            smali_dirs+=("$smali_dir")
        fi

        method_line=$(grep -n "$target_method" "$smali_file" | cut -d ':' -f 1)
        register_number=$(tail -n +"$method_line" "$smali_file" | grep -m 1 "move-result" | tr -dc '0-9')
        move_result_end_line=$(awk -v ML=$method_line 'NR>=ML && /move-result /{print NR; exit}' "$smali_file")
        orginal_line_number=$method_line
        replace_with_command="const/4 v${register_number}, 0x0"
        { sed -i "${orginal_line_number},${move_result_end_line}d" "$smali_file" && sed -i "${orginal_line_number}i\\${replace_with_command}" "$smali_file"; } && blue "${smali_file}  修改成功" "${smali_file} patched"
        old_smali_dir=$smali_dir
    done < <(find tmp/services/smali/*/com/android/server/pm/ tmp/services/smali/*/com/android/server/pm/pkg/parsing/ -maxdepth 1 -type f -name "*.smali" -exec grep -H "$target_method" {} \; | cut -d ':' -f 1)

    ALLOW_NON_PRELOADS_SYSTEM_SHAREDUIDS='ALLOW_NON_PRELOADS_SYSTEM_SHAREDUIDS' 

    find tmp/services/ -type f -name "ReconcilePackageUtils.smali" | while read smali_file; do
        match_line=$(grep -n "sput-boolean .*${ALLOW_NON_PRELOADS_SYSTEM_SHAREDUIDS}" "$smali_file" | head -n 1)

        if [[ -n "$match_line" ]]; then
            line_number=$(echo "$match_line" | cut -d ':' -f 1)
            reg=$(echo "$match_line" | sed -n 's/.*sput-boolean \([^,]*\),.*/\1/p')

            echo "Found in $smali_file at line $line_number using register $reg"

            # 在该行前插入 const/4 vX, 0x1
            sed -i "${line_number}i\    const/4 $reg, 0x1" "$smali_file"
            echo "→ Patched successfully in $smali_file"
        else
            echo "× Not found in $smali_file"
        fi
    done

    java -jar bin/apktool/APKEditor.jar b -f -i tmp/services -o build/${app_patch_folder}/patched/services.jar 
    cp -rfv build/${app_patch_folder}/patched/services.jar build/portrom/images/system/system/framework/services.jar

fi

if [[ -f build/${app_patch_folder}/patched/framework.jar ]];then
    blue "复制已经处理过的framework.jar"
    cp -rfv build/${app_patch_folder}/patched/framework.jar build/portrom/images/system/system/framework/framework.jar
else
    cp -rf build/portrom/images/system/system/framework/framework.jar tmp/framework.jar
    if [[ -f devices/common/0001-core-framework-Introduce-OplusPropsHookUtils-V6.patch ]]; then
        java -jar bin/apktool/APKEditor.jar d -f -i tmp/framework.jar -o tmp/framework -no-dex-debug
        pushd tmp/framework 
        [[ -d .git ]] && rm -rf .git  
        git init
        git config user.name "patchuser"
        git config user.email "patchuser@example.com"
        git add . > /dev/null 2>&1
        git commit -m "Initial smali source" > /dev/null 2>&1
        echo "🔧 应用 patch 文件 0001-core-framework-Introduce-OplusPropsHookUtils-V6.patch ..."
        git apply ${work_dir}/devices/common/0001-core-framework-Introduce-OplusPropsHookUtils-V6.patch && echo "✅ Patch 应用成功" || echo "❌ Patch 应用失败"

        popd
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/framework -o build/${app_patch_folder}/patched/framework.jar 
        cp -rfv build/${app_patch_folder}/patched/framework.jar build/portrom/images/system/system/framework/framework.jar
    else
        echo "⚠️ 0001-core-framework-Introduce-OplusPropsHookUtils-V6.patch不存在，跳过补丁应用"
    fi
fi


targetOplusService=$(find build/portrom/images/ -name "oplus-services.jar")
if [[ -f build/${app_patch_folder}/patched/oplus-services.jar ]];then
    blue "复制已经处理过的oplus-services.jar"
    cp -rfv build/${app_patch_folder}/patched/oplus-services.jar $targetOplusService

elif [[ -f $targetOplusService ]];then
    blue "Removing GSM Restriction"
    cp -rf $targetOplusService tmp/$(basename $targetOplusService).bak
    java -jar bin/apktool/APKEditor.jar d -f -i $targetOplusService -o tmp/OplusService
    targetSmali=$(find tmp -type f -name "OplusBgSceneManager.smali")
    python3 bin/patchmethod.py $targetSmali "-isGmsRestricted"
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/OplusService -o build/${app_patch_folder}/patched/oplus-services.jar
    cp -rfv build/${app_patch_folder}/patched/oplus-services.jar $targetOplusService

fi

if [[ ${base_device_family} == "OPSM8250" ]] || [[ ${base_device_family} == "OPSM8350" ]]; then
    blue "修复ColorOS15/OxygenOS15 人脸识解锁问题" "COS15/OOS15: Fix Face Unlock for SM8250/8350"
    #pushd tmp/services
    #patch -p1 < ${work_dir}/devices/${base_product_device}/0001-face-unlock-fix-for-op8t.patch
    #popd
	if ensure_resource_available "devices/common/face_unlock_fix_common.zip"; then
        rm -rf build/portrom/images/vendor/overlay/*
        unzip -o devices/common/face_unlock_fix_common.zip -d ${work_dir}/build/portrom/images/
        
    fi
	
    if ensure_resource_available "${work_dir}/devices/${base_product_device}/face_unlock_fix.zip" && [[ -f $old_face_unlock_app ]]; then
        unzip -o ${work_dir}/devices/${base_product_device}/face_unlock_fix.zip -d ${work_dir}/build/portrom/images/
        rm -rf build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal@1.0.so
        rm -rf build/portrom/images/odm/bin/hw/vendor.oneplus.faceunlock.hal@1.0-service
        rm -rf build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so
        rm -rf build/portrom/images/odm/etc/vintf/manifest/manifest_opfaceunlock.xml
        rm -rf build/portrom/images/odm/etc/init/vendor.oneplus.faceunlock.hal@1.0-service.rc
        rm -rf build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal@1.0.so
        rm -rf build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so


    fi
fi

if [[ ${base_android_version} == 13 ]] && [[ ${port_android_version} == 14 ]];then
    if ensure_resource_available "devices/common/a13_base_fix.zip"; then
        unzip -o devices/common/a13_base_fix.zip -d ${work_dir}/build/portrom/images/
        rm -rfv build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger@1.0-service \
            build/portrom/images/odm/bin/hw/vendor.oplus.hardware.wifi@1.1-service \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.felica@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.midas@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.wifi@1.1-service-qcom.rc \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_charger.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_felica.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_midas.xml \
            build/portrom/images/odm/etc/vintf/manifest/oplus_wifi_service_device.xml \
            build/portrom/images/odm/framework/vendor.oplus.hardware.wifi-V1.1-java.jar \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0-impl.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.wifi@1.1.so \
            build/portrom/images/odm/overlay/CarrierConfigOverlay.*.apk
    fi
fi

if [[ ${port_android_version} -ge 15 ]]; then
    if [[ ${base_device_family} == "OPSM8250" ]] && [[ ${base_android_version} != 13 ]];then
        if ensure_resource_available "devices/common/ril_fix_sm8250.zip"; then
            unzip -o devices/common/ril_fix_sm8250.zip -d ${work_dir}/build/portrom/images/
        fi
        rm -rf build/portrom/images/odm/lib/libmindroid-app.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys-V1-ndk_platform.so
    elif [[ ${base_device_family} == "OPSM8350" ]];then
        if ensure_resource_available "devices/common/ril_fix_sm8350.zip"; then
            unzip -o devices/common/ril_fix_sm8350.zip -d ${work_dir}/build/portrom/images/
        fi
        rm -rf build/portrom/images/odm/lib/libmindroid-app.so \
            build/portrom/images/odm/lib/libmindroid-framework.so \
            build/portrom/images/odm/lib/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib/vendor.oplus.hardware.subsys-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys-V1-ndk_platform.so
    fi

    if [[ ${base_android_version} == 14 ]]; then
        charger_v3=$(find build/portrom/images/odm/bin/hw/ -type f -name "vendor.oplus.hardware.charger-V3-service")
        if [[ -f $charger_v3 ]];then
        if ensure_resource_available "devices/common/charger-v6-update.zip"; then
            unzip -o devices/common/charger-v6-update.zip -d ${work_dir}/build/portrom/images/
        fi
        rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger-V3-service \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger-V3-service.rc \
            build/portrom/images/odm/lib/vendor.oplus.hardware.charger-V3-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.charger-V3-ndk_platform.so
        fi
    elif [[ ${base_android_version} == 13 ]];then
        #Ril Fix
        if ensure_resource_available "devices/common/ril_fix_a13_to_a15.zip"; then
            unzip -o devices/common/ril_fix_a13_to_a15.zip -d ${work_dir}/build/portrom/images/
        fi
        #Ril Fix for OxygenOS firmware (IN2013/IN2023)
        if ! grep -q "persist.vendor.radio.virtualcomm" build/portrom/images/odm/build.prop;then
            echo "persist.vendor.radio.virtualcomm=1" >> build/portrom/images/odm/build.prop
        fi
        rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.charger@1.0-service \
            build/portrom/images/odm/bin/hw/vendor.oplus.hardware.wifi@1.1-service \
            build/portrom/images/odm/etc/init/vendor.oneplus.faceunlock.hal@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.charger@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.felica@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.midas@1.0-service.rc \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.wifi@1.1-service-qcom.rc \
            build/portrom/images/odm/etc/vintf/manifest/manifest_opfaceunlock.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_charger.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_cryptoeng_hidl.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_felica.xml \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_midas.xml \
            build/portrom/images/odm/etc/vintf/manifest/oplus_wifi_service_device.xml \
            build/portrom/images/odm/framework/vendor.oplus.hardware.wifi-V1.1-java.jar \
            build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal@1.0.so \
            build/portrom/images/odm/lib/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal@1.0.so \
            build/portrom/images/odm/lib64/vendor.oneplus.faceunlock.hal-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0-impl.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.felica@1.0.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys_radio-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.subsys-V1-ndk_platform.so \
            build/portrom/images/odm/lib64/vendor.oplus.hardware.wifi@1.1.so
        #Nfc Fix
        if ensure_resource_available "devices/common/nfc_fix_for_a13.zip"; then
            unzip -o devices/common/nfc_fix_for_a13.zip -d ${work_dir}/build/portrom/images/
        fi
        rm -rf build/portrom/images/odm/bin/hw/vendor.oplus.hardware.nfc@1.0-service \
            build/portrom/images/odm/etc/init/vendor.oplus.hardware.nfc@1.0-service.rc \
            build/portrom/images/odm/etc/vintf/manifest/manifest_oplus_nfc.xml \
            build/portrom/images/odm/lib/vendor.oplus.hardware.nfc@1.0.so
        if ensure_resource_available "devices/common/cryptoeng_fix_a13.zip"; then
        # Fix Privacy related features(App lock、App hide)
            unzip -o devices/common/cryptoeng_fix_a13.zip -d ${work_dir}/build/portrom/images/
        fi
    fi
fi
echo "ro.surface_flinger.game_default_frame_rate_override=120" >>  build/portrom/images/vendor/default.prop
#Unlock AI CAll
#targetAICallAssistant=$(find build/portrom/images/ -name "HeyTapSpeechAssist.apk")
if [[ -f build/${app_patch_folder}/patched/HeyTapSpeechAssist.apk ]]; then
    blue "复制已经处理过的HeyTapSpeechAssist.apk"
    cp -rfv build/${app_patch_folder}/patched/HeyTapSpeechAssist.apk $targetAICallAssistant
elif [[ -f $targetAICallAssistant ]];then
        blue "Unlock AI Call"
        cp -rf $targetAICallAssistant tmp/$(basename $targetAICallAssistant).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetAICallAssistant -o tmp/HeyTapSpeechAssist $extra_args
        targetSmali=$(find tmp -type f -name "AiCallCommonBean.smali")
        python3 bin/patchmethod_v2.py $targetSmali getSupportAiCall -return true 
        find tmp/HeyTapSpeechAssist -type f -name "*.smali" -exec sed -i "s/sget-object \([vp][0-9]\+\), Landroid\/os\/Build;->MODEL:Ljava\/lang\/String;/const-string \1, \"PLG110\"/g" {} +
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/HeyTapSpeechAssist -o build/${app_patch_folder}/patched/HeyTapSpeechAssist.apk $extra_args
        cp -rfv build/${app_patch_folder}/patched/HeyTapSpeechAssist.apk $targetAICallAssistant 
fi
# patch_smali_with_apktool "HeyTapSpeechAssist.apk" "com/heytap/speechassist/aicall/setting/config/AiCallCommonBean.smali" ".method public final getSupportAiCall()Z/,/.end method" ".method public final getSupportAiCall()Z\n\t.locals 1\n\tconst\/4 v0, 0x1\n\treturn v0\n.end method" "regex"

ota_patched=false
if [[ $regionmark == "CN" ]];then
    cp -rf devices/common/OTA_CN.apk build/portrom/images/system_ext/app/OTA/OTA.apk && ota_patched=true

else
    cp -rf devices/common/OTA_IN.apk build/portrom/images/system_ext/app/OTA/OTA.apk && ota_patched=true
fi


if [[ $ota_patched == "false" ]];then
    # Remove OTA dm-verity
    targetOTA=$(find build/portrom/images/ -name "OTA.apk")
    if [[ -f build/${app_patch_folder}/patched/OTA.apk ]]; then
        blue "复制已经处理过的OTA.apk"
        cp -rfv build/${app_patch_folder}/patched/OTA.apk $targetOTA
    
    elif [[ -f $targetOTA ]];then
        blue "Removing OTA dm-verity"
        cp -rf $targetOTA tmp/$(basename $targetOTA).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetOTA -o tmp/OTA $extra_args
        targetSmali=$(find tmp -type f -path "*/com/oplus/common/a.smali")
        python3 bin/patchmethod_v2.py -d tmp/OTA -k ro.boot.vbmeta.device_state locked -return false 
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/OTA -o  build/${app_patch_folder}/patched/OTA.apk  $extra_args
         cp -rfv build/${app_patch_folder}/patched/OTA.apk $targetOTA
    fi
fi


    EXTEDNED_MODELS=("PJF110" "PEEM00" "PEDM00""LE2120" "LE2121" "LE2123" "KB2000" "KB2001" "KB2005" "KB2003" "LE2110" "LE2111" "LE2112" "LE2113" "IN2010" "IN2011" "IN2012" "IN2013" "IN2020" "IN2021" "IN2022" "IN2023")

    targetAIUnit=$(find build/portrom/images/ -name "AIUnit.apk")
    MODEL=PLG110
    #PKZ110 Reno 14 Pro
    #CPH2723 OnePlus 13s
    #CPH2671 #Oppo Find N5 Global
    #CPH2749 OnePlus 15
    [[ $regionmark != CN ]] && MODEL=CPH2745

    if [[ -f build/${app_patch_folder}/patched/AIUnit.apk ]]; then
            blue "复制已经处理过的OTA.apk"
            cp -rfv build/${app_patch_folder}/patched/AIUnit.apk $targetAIUnit
        
    elif [[ -f $targetAIUnit ]];then
        blue "Unlock High-End AI features, Device Model: $MODEL"
        cp -rf $targetAIUnit tmp/$(basename $targetAIUnit).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetAIUnit -o tmp/AIUnit $extra_args
        find tmp/AIUnit -type f -name "*.smali" -exec sed -i "s/sget-object \([vp][0-9]\+\), Landroid\/os\/Build;->MODEL:Ljava\/lang\/String;/const-string \1, \"$MODEL\"/g" {} +
        targetSmali=$(find tmp -type f -name "UnitConfig.smali")
        python3 bin/patchmethod_v2.py $targetSmali isAllWhiteConditionMatch
        python3 bin/patchmethod_v2.py $targetSmali isWhiteConditionsMatch
        python3 bin/patchmethod_v2.py $targetSmali isSupport

        unit_config_list=$(find tmp/AIUnit -type f -name "unit_config_list.json")
        jq --arg models_str "${EXTEDNED_MODELS[*]}" '
    # 定义数组变量
    ($models_str | split(" ")) as $new_models
    |

    # 开始对输入 JSON 数组执行 map
    map(
        if has("whiteModels") and (.whiteModels | type) == "string" then
        .whiteModels as $current |
        if $current == "" then
            .whiteModels = ($new_models | join(","))
        else
            ($current | split(",")) as $existing_models |
            ($new_models | map(select(. as $m | $existing_models | index($m) == null))) as $unique_models |
            if ($unique_models | length) > 0 then
            .whiteModels = $current + "," + ($unique_models | join(","))
            else . end
        end
        else . end
        |

        if has("minAndroidApi") then .minAndroidApi = 30 else . end
    )
    ' $unit_config_list > ${unit_config_list}.bak && mv ${unit_config_list}.bak ${unit_config_list}
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/AIUnit -o build/${app_patch_folder}/patched/AIUnit.apk  $extra_args
        cp -rfv build/${app_patch_folder}/patched/AIUnit.apk $targetAIUnit 
    fi

if [[ $port_android_version == 16 ]] && [[ $base_android_version -lt 15 ]] ;then
    # workaround fix AI Eraser
    cp build/portrom/images/odm/lib64/libaiboost.so build/portrom/images/my_product/lib64/libaiboost.so
    # sed -i 's|^/odm/lib64/libaiboost\.so.*$|/odm/lib64/libaiboost\.so u:object_r:same_process_hal_file:s0|' build/portrom/images/config/odm_file_contexts
    # echo "/(vendor|odm)/lib(64)?/libaiboost\.so  u:object_r:same_process_hal_file:s0" >> build/portrom/images/vendor/etc/selinux/vendor_file_contexts
fi

if ensure_resource_available "devices/common/xeutoolbox.zip" && [[ $base_android_version -lt 15 ]] && [[ ${portIsColorOSGlobal} != true ]];then
    blue "Integrated Xiami EU xeutoolbox"
    # this causes OOS/Cos 16.0.1 boot into bootloader
    #python3 bin/insert_selinux_policy.py build/portrom/images/system_ext/etc/selinux/system_ext_sepolicy.cil --config ${work_dir}/devices/common/xeu_toolbox_policy.json
    #echo "/system_ext/xbin/xeu_toolbox  u:object_r:xeu_toolbox_exec:s0" >> build/portrom/images/config/system_ext_file_contexts
    echo "/system_ext/xbin/xeu_toolbox  u:object_r:toolbox_exec:s0" >> build/portrom/images/config/system_ext_file_contexts
    echo "/system_ext/xbin/xeu_toolbox  u:object_r:toolbox_exec:s0" >> build/portrom/images/system_ext/etc/selinux/system_ext_file_contexts
    echo "(allow init toolbox_exec (file ((execute_no_trans))))" >> build/portrom/images/system_ext/etc/selinux/system_ext_sepolicy.cil
    unzip -o devices/common/xeutoolbox.zip -d build/portrom/images/
elif [[ $base_android_version -lt 15 ]];then
    targetGallery=$(find build/portrom/images/ -name "OppoGallery2.apk")
    if [[ -f build/${app_patch_folder}/patched/OppoGallery2.apk ]]; then
            blue "复制已经处理过的OppoGallery2"
            cp -rfv build/${app_patch_folder}/patched/OppoGallery2.apk $targetGallery
        
    elif [[ -f $targetGallery ]];then
        blue "Unlock AI Editor"
        cp -rf $targetGallery tmp/$(basename $targetGallery).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetGallery -o tmp/Gallery $extra_args
        python3 bin/patchmethod_v2.py -d tmp/Gallery -k "const-string.*\"ro.product.first_api_level\"" -hook "     const/16 reg, 0x22" 
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/Gallery -o build/${app_patch_folder}/patched/OppoGallery2.apk $extra_args
        cp -rfv build/${app_patch_folder}/patched/OppoGallery2.apk $targetGallery 
    fi
fi

if [[ ${base_device_family} == "OPSM8250" ]] || [[ ${base_device_family} == "OPSM8350" ]];then
    # Patch Battery Health Maximum capacity
    targetBattery=$(find build/portrom/images/ -name "Battery.apk")
    if [[ -f build/${app_patch_folder}/patched/Battery.apk ]]; then
        blue "复制已经处理过的Battery"
        cp -rfv build/${app_patch_folder}/patched/Battery.apk $targetBattery
     
    elif  [[ -f $targetBattery ]];then
        blue "Patch Battery Health Maximum capacity"
        cp -rf $targetBattery tmp/$(basename $targetBattery).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetBattery -o tmp/Battery $extra_args
        python3 bin/patchmethod_v2.py -d tmp/Battery/ -k "getUIsohValue" -m devices/common/patch_battery_soh.txt 
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/Battery -o build/${app_patch_folder}/patched/Battery.apk $extra_args
        cp -rfv build/${app_patch_folder}/patched/Battery.apk $targetBattery 
    fi
fi 

if [[ ${regionmark} != "CN" ]] && [[ ${base_product_model} != "IN20*" ]];then

    # Charging info in Settings
    targetSettings=$(find build/portrom/images/ -name "Settings.apk")

    if [[ -f $targetSettings ]];then
        blue "Charging info in Settings"
        cp -rf $targetSettings tmp/$(basename $targetSettings).bak
        java -jar bin/apktool/APKEditor.jar d -f -i $targetSettings -o tmp/Settings $extra_args
        targetSmali=$(find tmp -type f -name "DeviceChargeInfoController.smali")
        python3 bin/patchmethod_v2.py $targetSmali isPreferenceSupport
        java -jar bin/apktool/APKEditor.jar b -f -i tmp/Settings -o $targetSettings $extra_args
    fi
fi 

targetOplusLauncher=$(find build/portrom/images/ -name "OplusLauncher.apk")

if [[ -f $targetOplusLauncher ]] && [[ $base_product_first_api_level -gt 34 ]];then
	blue "解锁运存显示"
	cp -rf $targetOplusLauncher tmp/$(basename $targetOplusLauncher).bak
	java -jar bin/apktool/APKEditor.jar d -f -i $targetOplusLauncher -o tmp/OplusLauncher $extra_args
	targetSmali=$(find tmp -type f -path "*/com/oplus/basecommon/util/SystemPropertiesHelper.smali")
 python3 bin/patchmethod_v2.py $targetSmali getFirstApiLevel ".locals 1\n\tconst/16 v0, 0x22\n\treturn v0"
 java -jar bin/apktool/APKEditor.jar b -f -i tmp/OplusLauncher -o $targetOplusLauncher $extra_args
fi

targetSystemUI=$(find build/portrom/images/ -name "SystemUI.apk")
if [[ -f build/${app_patch_folder}/patched/SystemUI.apk ]]; then
        blue "复制已经处理过的SystemUI.apk"
        cp -rfv build/${app_patch_folder}/patched/SystemUI.apk $targetSystemUI
     
elif [[ -f "$targetSystemUI" ]]; then
    
    cp -rf $targetSystemUI tmp/$(basename $targetSystemUI).bak
    java -jar bin/apktool/APKEditor.jar d -f -i $targetSystemUI -o tmp/SystemUI $extra_args
    blue "解锁全景全屏AOD"
    targetSmoothTransitionControllerSmali=$(find tmp/SystemUI -type f -name "SmoothTransitionController.smali")
    python3 bin/patchmethod_v2.py "$targetSmoothTransitionControllerSmali" setPanoramicStatusForApplication
    python3 bin/patchmethod_v2.py "$targetSmoothTransitionControllerSmali" setPanoramicSupportAllDayForApplication

    targetAODDisplayUtilSmali=$(find tmp/SystemUI -type f -name "AODDisplayUtil.smali")
    python3 bin/patchmethod_v2.py "$targetAODDisplayUtilSmali" isPanoramicProcessTypeNotSupportAllDay -return false
    if [[ $base_product_first_api_level -gt 34 ]];then
    targetStatusBarFeatureOptionSmali=$(find tmp/SystemUI -type f -name "StatusBarFeatureOption.smali")
    python3 bin/patchmethod_v2.py "$targetStatusBarFeatureOptionSmali" isChargeVoocSpecialColorShow -return true
    fi
    if [[ $regionmark != "CN" ]];then
        blue "解锁MyDevice"
        targetSmali=$(find tmp -type f -name "FeatureOption.smali")
        python3 bin/patchmethod_v2.py $targetSmali isSupportMyDevice
    fi
    # tmp workround 
    for style_xml_file in $(find tmp/SystemUI -name "styles.xml");do 
        sed -i "s/style\/null/7f1403f6/g" $style_xml_file
    done
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/SystemUI -o build/${app_patch_folder}/patched/SystemUI.apk $extra_args
    cp -rfv build/${app_patch_folder}/patched/SystemUI.apk $targetSystemUI
fi

targetAOD=$(find build/portrom/images/ -name "Aod.apk")

if [[ -f $targetAOD ]] && [[ $base_product_first_api_level -le 35 ]] ;then
	blue "强制开启老机型AOD全天候息屏功能"
	cp -rf $targetAOD tmp/$(basename $targetAOD).bak
	java -jar bin/apktool/APKEditor.jar d -f -i $targetAOD -o tmp/Aod $extra_args
	targetCommonUtilsSmali=$(find tmp -type f -path "*/com/oplus/aod/util/CommonUtils.smali")
    targetSettingsSmali=$(find tmp -type f -path "*/com/oplus/aod/util/SettingsUtils.smali")
    python3 bin/patchmethod_v2.py $targetCommonUtilsSmali isSupportFullAod -return true
    python3 bin/patchmethod_v2.py $targetSettingsSmali getKeyAodAllDaySupportSettings -return true
    java -jar bin/apktool/APKEditor.jar b -f -i tmp/Aod -o $targetAOD $extra_args
fi
yellow "删除多余的App" "Debloating..." 
# List of apps to be removed

debloat_apps=("HeartRateDetect" "Browser" "ConsumerIRApp" "ADS" "KeKePay" "OplusSecurityKeyboard" "Pictorial" "LinktoWindows" "KeKeAppDetail")
#kept_apps=("Clock" "FileManager" "KeKeThemeSpace" "SogouInput" "Weather" "Calendar")
#kept_apps=("BackupAndRestore" "Calculator2" "Calendar" "Clock" "FileManager" "OppoNote2" "OppoWeather2" "UPTsmService" "Music")
kept_apps=("Weather" "Calendar" "Clock" "FileManager" "OppoNote2" "OppoWeather2")
#kept_apps=()

if [[ $super_extended == "true" ]] && [[ $pack_method == "stock" ]] && [[ -f build/baserom/images/reserve.img ]]; then
    rm -rf build/baserom/images/reserve.img
elif [[ $super_extended == "false" ]] && [[ $pack_method == "stock" ]] && [[ -f build/baserom/images/reserve.img ]]; then
    #extract_partition "${work_dir}/build/baserom/images/reserve.img" "${work_dir}/build/baserom/images/"
    #if [[ -f ext/del-app-ksu-module/system/product/app/* ]];then
    ##    rm -rf ext/del-app-ksu-module/system/product/app/*
    #fi
    #ext_moudle_app_folder="ext/del-app-ksu-module/system/product/app"
    for delapp in $(find build/portrom/images/ -maxdepth 3 -path "*/del-app/*" -type d);do
        
        app_name=$(basename "$delapp")

        # Check if the app is in kept_apps, skip if true
        if [[ " ${kept_apps[@]} " =~ " ${app_name} " ]]; then
            echo "Skipping kept app: $app_name"
        continue
        fi
        #mv -fv $delapp ${ext_moudle_app_folder}/
        rm -rfv $delapp 
    done 

    for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done

    cp -rfv devices/common/via build/portrom/images/product/app/
elif [[ $super_extended == "false" ]] && [[ $base_product_model == "KB2000" ]] && [[ "$is_ab_device" == true ]];then
    for delapp in $(find build/portrom/images/ -maxdepth 3 -path "*/del-app/*" -type d ); do
        app_name=$(basename ${delapp})
        
        keep=false
        for kept_app in "${kept_apps[@]}"; do
            if [[ $app_name == *"$kept_app"* ]]; then
                keep=true
                break
            fi
        done
        
        if [[ $keep == false ]]; then
            debloat_apps+=("$app_name")
        fi

    done
    for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done
elif [[ $super_extended == "false" ]] && [[ $base_product_model == "KB200"* ]] && [[ "$is_ab_device" == true ]];then
    debloat_apps=("Facebook" "YTMusic" "GoogleHome" "GoogleOne" "Videos_del" "Drive_del" "ConsumerIRApp" "YouTube" "Gmail2" "Maps" "Wellbeing" "OPForum" "INOnePlusStore" "YTMusic_del" "ConsumerIRApp" "Meet")
    for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done
    
    #rm -rfv build/portrom/images/my_stock/del-app/*
elif [[ $super_extended == "false" ]] && [[ $base_product_model == "LE2101" ]];then
      debloat_apps=("Facebook" "YTMusic" "GoogleHome" "GoogleOne" "Videos_del" "Drive_del" "ConsumerIRApp" "YouTube" "Gmail2" "Maps" "Wellbeing" "OPForum" "INOnePlusStore" "YTMusic_del" "ConsumerIRApp" "Meet")
    for debloat_app in "${debloat_apps[@]}"; do
    # Find the app directory
    app_dir=$(find build/portrom/images/ -type d -name "*$debloat_app*")
    
    # Check if the directory exists before removing
    if [[ -d "$app_dir" ]]; then
        yellow "删除目录: $app_dir" "Removing directory: $app_dir"
        rm -rfv "$app_dir"
    fi
    done
  #rm -rfv build/portrom/images/my_stock/del-app/*
fi
rm -rf build/portrom/images/product/etc/auto-install*
rm -rf build/portrom/images/system/verity_key
rm -rf build/portrom/images/vendor/verity_key
rm -rf build/portrom/images/product/verity_key
rm -rf build/portrom/images/system/recovery-from-boot.p
rm -rf build/portrom/images/vendor/recovery-from-boot.p
rm -rf build/portrom/images/product/recovery-from-boot.p

# build.prop 修改

sed -i "/ro.oplus.audio.*/d" build/portrom/images/my_product/build.prop

prepare_base_prop
add_prop_from_port

blue "正在修改 build.prop" "Modifying build.prop"


#change the locale to English
export LC_ALL=en_US.UTF-8
buildDate=$(date -u +"%a %b %d %H:%M:%S UTC %Y")
buildUtc=$(date +%s)
for i in $(find build/portrom/images -type f -name "build.prop");do
    blue "正在处理 ${i}" "modifying ${i}"
    # sed -i "s/ro.build.date=.*/ro.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.build.date.utc=.*/ro.build.date.utc=${buildUtc}/g" ${i}
    # sed -i "s/ro.odm.build.date=.*/ro.odm.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.odm.build.date.utc=.*/ro.odm.build.date.utc=${buildUtc}/g" ${i}
    # sed -i "s/ro.vendor.build.date=.*/ro.vendor.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.vendor.build.date.utc=.*/ro.vendor.build.date.utc=${buildUtc}/g" ${i}
    # sed -i "s/ro.system.build.date=.*/ro.system.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.system.build.date.utc=.*/ro.system.build.date.utc=${buildUtc}/g" ${i}
    # sed -i "s/ro.product.build.date=.*/ro.product.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.product.build.date.utc=.*/ro.product.build.date.utc=${buildUtc}/g" ${i}
    # sed -i "s/ro.system_ext.build.date=.*/ro.system_ext.build.date=${buildDate}/g" ${i}
    # sed -i "s/ro.system_ext.build.date.utc=.*/ro.system_ext.build.date.utc=${buildUtc}/g" ${i}
    sed -i "s/persist.sys.timezone=.*/persist.sys.timezone=Asia\/Shanghai/g" ${i}
    #全局替换device_code
    sed -i "s/$port_device_code/$base_device_code/g" ${i}
    sed -i "s/$port_product_model/$base_product_model/g" ${i}
    sed -i "s/$port_product_name/$base_product_name/g" ${i}
    sed -i "s/$port_my_product_type/$base_my_product_type/g" ${i}
    sed -i "s/$port_product_device/$base_product_device/g" ${i}
    # 添加build user信息
    sed -i "s/ro.build.user=.*/ro.build.user=${build_user}/g" ${i}
    sed -i "s/ro.build.display.id=.*/ro.build.display.id=${target_display_id}/g" ${i}
    sed -i "s/ro.oplus.radio.global_regionlock.enabled=.*/ro.oplus.radio.global_regionlock.enabled=false/g" ${i}
    sed -i "s/persist.sys.radio.global_regionlock.allcheck=.*/persist.sys.radio.global_regionlock.allcheck=false/g" ${i}
    sed -i "s/ro.oplus.radio.checkservice=.*/ro.oplus.radio.checkservice=false/g" ${i}
    if [[ $portIsColorOSGlobal == true ]];then
        sed -i 's/=OnePlus[[:space:]]*$/=OPPO/' ${i}
    fi

done

sed -i "s/ro.vendor.oplus.market.name=.*/ro.vendor.oplus.market.name=${base_market_name}/g" build/portrom/images/my_product/etc/bruce/build.prop
sed -i "s/ro.vendor.oplus.market.enname=.*/ro.vendor.oplus.market.enname=${base_market_name}/g" build/portrom/images/my_product/etc/bruce/build.prop

remove_prop_v2 "persist.oplus.software.audio.right_volume_key"
remove_prop_v2 "persist.oplus.software.alertslider.location"


sed -i -e '$a\'$'\n''persist.adb.notify=0' build/portrom/images/system/system/build.prop
sed -i -e '$a\'$'\n''persist.sys.usb.config=mtp,adb' build/portrom/images/system/system/build.prop
sed -i -e '$a\'$'\n''persist.sys.disable_rescue=true' build/portrom/images/system/system/build.prop

base_rom_density=$(grep "ro.sf.lcd_density" --include="*.prop" -r build/baserom/images/my_product | head -n 1 | cut -d "=" -f2)
[ -z ${base_rom_density} ] && base_rom_density=480

# if grep -q "ro.sf.lcd_density" build/portrom/images/my_product/build.prop ;then
#         sed -i "s/ro.sf.lcd_density=.*/ro.sf.lcd_density=${base_rom_density}/g" build/portrom/images/my_product/build.prop
# else
#         echo "ro.sf.lcd_density=${base_rom_density}" >> build/portrom/images/my_product/build.prop
# fi

# brand require lowercase 
if [[ ${base_vendor_brand,,} != ${port_vendor_brand,,} ]] && [[ $portIsColorOSGlobal == false ]] && [[ $port_android_version -lt 16 ]];then
    # Global ColorOS needs to be Oppo brand or stuck on 
    sed -i "s/ro.oplus.image.system_ext.brand=.*/ro.oplus.image.system_ext.brand=${base_vendor_brand,,}/g" build/portrom/images/system_ext/etc/build.prop
fi

# fix bootloop
if [[ -f build/baserom/images/my_product/etc/extension/sys_game_manager_config.json ]];then
    cp -rf build/baserom/images/my_product/etc/extension/sys_game_manager_config.json build/portrom/images/my_product/etc/extension/
else
    rm -rf build/portrom/images/my_product/etc/extension/sys_game_manager_config.json
fi

if [[ ! -f build/baserom/images/my_product/etc/extension/sys_graphic_enhancement_config.json ]];then
    rm -rf build/portrom/images/my_product/etc/extension/sys_graphic_enhancement_config.json
else
    cp -rf build/baserom/images/my_product/etc/extension/sys_graphic_enhancement_config.json build/portrom/images/my_product/etc/extension/
fi

if [[ $(cat build/baserom/images/my_product/build.prop | grep "ro.oplus.audio.effect.type" | cut -d "=" -f 2) == "dolby" ]] ;then
blue "修复杜比音效+多应用音量调节 SM8250/SM8350" "Fix Dolby + App Specific volume adjustment for SM8250/SM8350"
     #cp $source_dolby_lib build/portrom/images/system_ext/lib64/
     cp build/baserom/images/my_product/etc/permissions/oplus.product.features_dolby_stereo.xml build/portrom/images/my_product/etc/permissions/oplus.product.features_dolby_stereo.xml
     if ensure_resource_available "devices/common/dolby_fix.zip"; then
         unzip -o devices/common/dolby_fix.zip -d build/portrom/images/ 
     fi
fi


# Fix wechat/whatsapp volume isue
cp -rf build/baserom/images/my_product/etc/audio*.xml build/portrom/images/my_product/etc/
cp -rf build/baserom/images/my_product/etc/default_volume_tables.xml build/portrom/images/my_product/etc/
if [[ -d build/baserom/images/my_product/etc/breenospeech2 ]];then
    cp -rf build/baserom/images/my_product/etc/breenospeech2/* build/portrom/images/my_product/etc/breenospeech2/
fi
rm -rf build/portrom/images/my_product/etc/fusionlight_profile/*
cp -rf build/baserom/images/my_product/etc/fusionlight_profile/*  build/portrom/images/my_product/etc/fusionlight_profile/
# Fix game audio issue on 15.0.2 (13t)


sed -i "/persist.vendor.display.pxlw.iris_feature=.*/d" build/portrom/images/my_product/etc/bruce/build.prop

if grep -q "ro.build.version.oplusrom.display" build/portrom/images/my_manifest/build.prop;then
    sed -i '/^ro.build.version.oplusrom.display=/ s/$/ ❤️ By Co-CreateTeam /' build/portrom/images/my_manifest/build.prop
else
    sed -i '/^ro.build.version.oplusrom.display=/ s/$/ ❤️ By Co-CreateTeam /' build/portrom/images/my_product/etc/bruce/build.prop
fi

if [[ $portIsRealmeUI == true ]];then
    case $port_android_version in
        16) rui_version=7.0;;
        15) rui_version=6.0;;
        14) rui_version=5.0;;
    esac
    echo "ro.build.version.realmeui=$rui_version" >> build/portrom/images/my_product/etc/bruce/build.prop

fi

propfile="build/portrom/images/my_product/etc/bruce/build.prop"

if [[ $portIsColorOSGlobal == true ]]; then
    MODEL_MAGIC="CPH2659,BRAND:OPPO"
    MODEL_AIUNIT="CPH2659,BRAND:OPPO"

elif [[ $portIsOOS == true ]]; then
    MODEL_MAGIC="CPH2659,BRAND:OPPO"
    MODEL_AIUNIT="CPH2745,BRAND:OnePlus"

else
    MODEL_MAGIC="PLK110,BRAND:OnePlus"
    MODEL_AIUNIT="PLK110,BRAND:OnePlus"
fi

{
    echo "persist.oplus.prophook.com.oplus.ai.magicstudio=MODEL:${MODEL_MAGIC}"
    echo "persist.oplus.prophook.com.oplus.aiunit=MODEL:${MODEL_AIUNIT}"
} >> "$propfile"

if [[ $port_vendor_brand == "realme" ]];then
    echo "persist.oplus.prophook.com.coloros.smartsidebar=\"BRAND:realme\"" >> "$propfile"
fi
remove_prop_v2 "ro.oplus.resolution"
remove_prop_v2 "ro.oplus.display.wm_size_resolution_switch.support"
remove_prop_v2 "ro.density.screenzoom"
remove_prop_v2 "ro.oplus.resolution"
remove_prop_v2 "ro.oplus.density.qhd_default"
remove_prop_v2 "ro.oplus.density.fhd_default"
remove_prop_v2 "ro.oplus.key.actionbutton"
remove_prop_v2 "ro.oplus.audio.support.foldingmode"
remove_prop_v2 "ro.config.fold_disp"
remove_prop_v2 "persist.oplus.display.fold.support"
remove_prop_v2 "ro.oplus.haptic"

remove_prop_v2 "ro.vendor.mtk"
remove_prop_v2 "ro.oplus.mtk"
# OnePlus 8T: Fix OpSynergy crash 
remove_prop_v2 "persist.sys.oplus.wlan.atpc.qcom_use_iw"

remove_prop_v2 "ro.product.oplus.cpuinfo"
remove_prop_v2
if [[ $base_android_version -lt 15 ]] && [[ $port_android_version -gt 15 ]];then
    remove_prop_v2 "ro.lcd.display.screen" 
    remove_prop_v2 "ro.display.brightness"
    remove_prop_v2 "ro.oplus.lcd.display"
    #remove_prop_v2 "ro.display.brightness.curve.name" force
fi

add_prop_v2 "ro.oplus.game.camera.support_1_0" "true"
add_prop_v2 "ro.oplus.audio.quiet_start" "true"
if [[ $portIsOOS == "true" ]];then
    remove_prop_v2 "ro.oplus.camera.quickshare.support" force
fi

if [[ $port_android_version -lt 16 ]];then

    if [[ $base_device_family == "OPSM8250" ]] || [[ $base_device_family == "OPSM8350" ]];then
        add_prop_v2 "persist.sys.oplus.anim_level" "2"
    else
        add_prop_v2 "persist.sys.oplus.anim_level" "1"
    fi
fi
add_prop_v2 "ro.sf.lcd_density" "${base_rom_density}"

cp -rf build/baserom/images/my_product/app/com.oplus.vulkanLayer build/portrom/images/my_product/app/
cp -rf build/baserom/images/my_product/app/com.oplus.gpudrivers.* build/portrom/images/my_product/app/

mkdir -p tmp/etc/permissions tmp/etc/extension
cp -fv build/portrom/images/my_product/etc/permissions/*.xml tmp/etc/permissions/
cp -fv build/portrom/images/my_product/etc/extension/*.xml tmp/etc/extension/
cp -rf build/baserom/images/my_product/etc/permissions/*.xml build/portrom/images/my_product/etc/permissions/
find tmp/etc/permissions/ -type f \( -name "multimedia*.xml" -o -name "*permissions*.xml" -o -name "*google*.xml"  -o -name "*configs*.xml" -o -name "*gsm*.xml" -o -name "feature_activity_preload.xml" -o -name "*gemini*.xml" -o -name "*gms*.xml" \) -exec cp -fv {} build/portrom/images/my_product/etc/permissions/ \;


if [[ $regionmark != "CN" ]];then
   for i in com.android.contacts com.android.incallui com.android.mms com.oplus.blacklistapp com.oplus.phonenoareainquire com.ted.number; do 
        sed -i "/$i/d" build/portrom/images/my_stock/etc/config/app_v2.xml
   done
fi

cp -rf build/baserom/images/my_product/etc/permissions/*.xml build/portrom/images/my_product/etc/permissions/
cp -rf build/baserom/images/my_product/etc/extension/*.xml build/portrom/images/my_product/etc/extension/
cp -rf  build/baserom/images/my_product/etc/refresh_rate_config.xml build/portrom/images/my_product/etc/refresh_rate_config.xml

#cp -rf build/baserom/images/my_product/etc/extension/*.xml build/portrom/images/my_product/etc/extension/

cp -rf  build/baserom/images/my_product/etc/sys_resolution_switch_config.xml build/portrom/images/my_product/etc/sys_resolution_switch_config.xml

cp -rf build/baserom/images/my_product/etc/permissions/com.oplus.sensor_config.xml build/portrom/images/my_product/etc/permissions/
# add_feature "com.android.systemui.support_media_show" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml

# Features Extension

oplus_features=(
    "oplus.software.directservice.finger_flashnotes_enable^小布记忆" 
    "oplus.software.support_quick_launchapp"  
    "oplus.software.support_blockable_animation" 
    "oplus.software.support.zoom.multi_mode" 
    #"oplus.software.radio.networkless_support^无网畅聊" 
    #"oplus.software.display.ai_eyeprotect_v1_support^AI护眼"
    "oplus.software.display.reduce_white_point^降低白点值"
    "oplus.software.audio.media_control"
    "oplus.software.support.zoom.open_wechat_mimi_program"
    "oplus.software.support.zoom.center_exit"
    "oplus.software.support.zoom.game_enter" 
    "oplus.software.coolex.support"
    "oplus.software.display.game.dapr_enable"
    "oplus.software.display.eyeprotect_game_support"
    "oplus.software.multi_app.volume.adjust.support^多音量调节（A13机型没有）" 
    "oplus.software.systemui.navbar_pick_color^15.0.2.201新增"
    "oplus.software.string_gc_support"
    "oplus.software.display.rgb_ball_support^色温调节球"
    "oplus.software.camera_volume_quick_launch" #GT5Pro
    "oplus.software.display.intelligent_color_temperature_support"
    "oplus.software.display.oha_support"
    "oplus.software.display.smart_color_temperature_rhythm_health_support"
    "oplus.software.display.mura_enhance_brightness_support"
    "oplus.software.audio.assistant_volume_support"
    "oplus.software.audio.volume_default_adjust"
    "oplus.software.notification_alert_support_fifo"
    "oplus.software.game_scroff_act_preload"
    "oplus.software.display.game_dark_eyeprotect_support^游戏助手夜晚护眼"
    "oplus.software.systemui.navbar_pick_color^小横条拾取颜色优化"
    "oplus.software.smart_sidebar_video_assistant^侧边栏视频助手"
    "oplus.video.audio.volume.enhancement^视频音量增强" 
    "oplus.software.display.lux_small_debounce_expand_support"
    "oplus.hardware.display.no_bright_eyes_low_freq_strobe^低亮度屏闪"
    "oplus.software.audio.super_volume_4x^400%超级音量"
    "oplus.software.radio.networkless_sms_support"
    "com.oplus.location.car_phone_connection"
   "oplus.software.display.enhance_brightness_with_uidimming^LocalHDR"
    "oplus.software.adaptive_smooth_animation^山海通信网络引擎"
    "oplus.software.radio.ai_link_boost"
    "oplus.software.radio.ai_link_boost_notification"
    "oplus.software.radio.ai_link_boost_railway_notification"
    "oplus.software.systemui.pin_task^钉到流体云"
    "oplus.software.radio.hfp_comm_shared_support^iPhone互联"
    "oplus.hardware.display.motion_sickness^晕动舒缓提示"
    "oplus.software.radio.nwpower_amc_special_sim"
    "oplus.software.radio.mdlog_buffer_qdss_enable"
    "oplus.software.radio.hfp_comm_shared_support"
)

for oplus_feature in ${oplus_features[@]}; do 
    add_feature_v2 oplus_feature $oplus_feature
done

if [[ $vndk_version -gt 33 ]];then
 add_feature_v2 oplus_feature "oplus.software.radio.networkless_support^无网畅聊"
fi
#add_feature "com.android.systemui.aod_notification_infor_text" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
#add_feature 'com.oplus.mediacontroller.fluidConfig^^args=\"String:{&quot;statusbar_enable_default&quot;:1}' build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml


app_features=(
    "os.personalization.flip.agile_window.enable"
    "os.personalization.wallpaper.live.ripple.enable"
    "com.oplus.infocollection.screen.recognition"
    "os.graphic.gallery.os15_secrecy^^args=\"boolean:true\""
    "com.coloros.colordirectservice.cm_enable^^args=\"boolean:true\""
    "com.oplus.exserviceui.feature_zoom_drag"
    "feature.hottouch.anim.support"
    "os.charge.settings.longchargeprotection.ai"
    "os.charge.settings.smartchargeswitch.open"
    "com.oplus.eyeprotect.ai_intelligent_eye_protect_support"
    "com.android.settings.network_access_permission"
    "os.charge.settings.batterysettings.batteryhealth^电池健康度"
    "com.oplus.mediaturbo.service"
    "com.oplus.mediaturbo.game_live^直播助手"
    "oplus.aod.wakebyclick.support^点击屏幕唤醒息屏"
    "com.oplus.screenrecorder.area_record^区域截图^args=\"boolean:true\""
    "com.oplus.systemui.panoramic_aod.enable^^args=\"boolean:true\""
    "com.android.systemui.qs_deform_enable^^args=\"boolean:true\""
    "com.oplus.mediaturbo.tencent_meeting^腾讯会议^args=\"boolean:true\""
    "com.oplus.note.aigc.ai_rewrtie.support^AI帮写"
    #"feature.super_settings_smart_touch_v2.support^隔膜触控V2"
    "com.oplus.games.show_bypass_charging_when_gameapps^旁路供电^args=\"boolean:true\""
    "com.oplus.wallpapers.livephoto_wallpaper^^args=\"boolean:true\""
    "com.oplus.battery.autostart_limit_num^^args=\"String:8|10-16|15-24|20\""
    "com.android.launcher.recent_lock_limit_num^^args=\"String:8|10-16|15-24|20\""
    "com.oplus.battery.whitelist_vowifi^^args=\"boolean:true\""
    "com.oplus.battery.support.smart_refresh" # GT5Pro
    "com.oplus.battery.life.mode.notificate^^args=\"int:1\"" # 13T indicate if the device is support life mode 1.0：1 2.0：2 
    "feature.support.game.AI_PLAY" #GT5Pro
    "feature.support.game.AI_PLAY_version3" # GT5Pro

    "feature.super_app_alive.support_min_ram^^args=\"int:12\""
    "feature.super_app_alive.support_flag^^args=\"int:15\""
    "feature.super_alive_game.support^^args=\"int:1\""
    "feature.super_settings_smart_touch.support^隔膜触控V1"
    "com.android.launcher.folder_content_recommend_disable"
    "com.android.launcher.rm_disable_folder_footer_ad"
    "feature.support.game.ASSIST_KEY"
    "oplus.software.vibration_custom"
    "com.oplus.smartmediacontroller.lss_assistant_enable^侧边栏声音分轨助手"
    # "com.android.incallui.share_screen_and_touch_cmd_support^电话触摸分享与屏幕共享" 会导致OOS 拨打电话崩溃
    "com.oplus.phonemanager.ai_voice_detect^合成语音^args=\"int:1\""
    "com.oplus.directservice.aitoolbox_enable^^args=\"boolean:true\""
    "com.coloros.support_gt_boost^^args=\"boolean:true\""
    "com.oplus.aicall.call_translate"
    "com.oplus.gesture.camera_space_gesture_support^隔空手势" #需要替换RM设备的OplusGesture App才能开启
    "com.oplus.gesture.intelligent_perception"
    "com.oplus.dmp.aiask_enable^AI搜索^args=\"int:1\""
    "os.graphic.gallery.photoeditor.aibesttake^最佳摄影功能^args=\"int:1\""
    "com.oplus.tips.os_recommend_page_index^新功能推荐^args=\"String:indexOS15_0_2_new\""
    "com.oplus.mediaturbo.transcoding^^args=\"boolean:true\""
    "com.android.launcher.app_advice_autoadd^^args=\"boolean:true\""
    "com.android.launcher.INDICATOR_BREENO_ENTRY_ENABLE^系统桌面小布提示^args=\"boolean:true\""
    #ColorOS 16 new added
    "com.oplus.systemui.panoramic_aod.enable^AOD^args=\"boolean:true\""
    "oplus.software.disable_aod_all_day_mode^^args=\"boolean:false\""
    "com.oplus.systemui.panoramic_aod_all_day_default_open.enable^^args=\"boolean:true\""
    "com.oplus.systemui.panoramic_aod_all_day.enable^^args=\"boolean:true\""
    "oplus_keyguard_panoramic_aod_all_day_support^^args=\"boolean:true\""
    "com.oplus.securityguard.sample.feature_enable^安全管家相关^args=\"boolean:true\""
    "com.oplus.aiwriter.input_entrance_enabled^^args=\"boolean:true\""
    "com.oplus.persona.card_datamining_support^^args=\"boolean:true\""
    "os.graphic.gallery.collage.livephoto^^args=\"boolean:true\""
    "com.android.systemui.qs_deform_enable^^args=\"boolean:true\""
    "com.oplus.wallpapers.ai_camera_movement^^args=\"boolean:true\""
    "com.oplus.wallpapers.livephoto_wallpaper_support_hdr^^args=\"boolean:true\""
    "com.oplus.wallpapers.livephoto_wallpaper_support_4k^^args=\"boolean:true\""
    "com.oplus.gallery3d.aihd_support"
    "os.graphic.gallery.collage.asset_bounds_break^出圈^args=\"boolean:true\""
    "os.graphic.gallery.collage.livephoto^^args=\"boolean:true\""
    "com.oplus.wallpapers.3d_wallpaper^3D壁纸^args=\"boolean:true\""
    "com.oplus.aipaint^^args=\"boolean:true\""
    "com.oplus.aipaint.function_switch^^args=\"boolean:true\""

)
for app_feature in ${app_features[@]}; do 
    add_feature_v2 app_feature $app_feature
done

 if [[ ${port_oplusrom_version} == "16.0.1" ]];then
    add_feature_v2  app_feature  "com.oplus.wallpapers.ai_camera_movement^^args=\"boolean:true\""
 else
    add_feature_v2  app_feature  "com.oplus.wallpapers.ai_camera_movement_for_products_before_15^^args=\"boolean:true\""
fi

add_feature_v2 permission_oplus_feature "oplus.software.game.cold.start.speedup.enable"
add_feature_v2 permission_feature "com.plus.press_power_botton_experiment"
add_feature_v2 permission_feature "oplus.video.hdr10_support"
add_feature_v2 permission_feature "oplus.video.hdr10plus_support"
add_feature_v2 permission_feature "oppo.display.screen.gloablehbm.support"
add_feature_v2 permission_feature "oppo.high.brightness.support"
add_feature_v2 permission_feature "oppo.multibits.dimming.support"
add_feature_v2 permission_feature "oplus.software.display.refreshrate_default_smart"
if [[ "${base_product_device}" == "OnePlus9Pro" ]] ;then
    add_feature_v2 app_feature "os.charge.settings.wirelesscharging.power^设置显示无线充电瓦数^args=\"int:50\"" "oplus.power.wirelesschgwhenwired.support" "com.oplus.battery.wireless.charging.notificate" "os.charge.settings.wirelesschargingcoil.position" "os.charge.settings.wirelesscharge.support"
elif [[ "${base_product_device}" == "OP4E3F" ]] || [[ "${base_product_device}" == "OP4E5D" ]];then
    add_feature_v2 app_feature "os.charge.settings.wirelesscharging.power^设置显示无线充电瓦数^args=\"int:30\"" "oplus.power.wirelesschgwhenwired.support" "com.oplus.battery.wireless.charging.notificate" "os.charge.settings.wirelesschargingcoil.position" "os.charge.settings.wirelesscharge.support"
else
  remove_feature "oplus.power.wirelesschgwhenwired.support"
  remove_feature "com.oplus.battery.wireless.charging.notificate"
  remove_feature "os.charge.settings.wirelesscharge.support"
  remove_feature "os.charge.settings.wirelesscharging.power"
  remove_feature "os.charge.settings.wirelesschargingcoil.position"
  remove_feature "oplus.power.onwirelesscharger.support"
fi

#通话录音限制
xmlstarlet ed -L -d '//app_feature[@name="com.android.incallui.support_call_record_prompt_mcc"]' build/portrom/images/my_stock/etc/extension/com.oplus.app-features.xml 

xmlstarlet ed -L -d '//app_feature[@name="com.android.incallui.hide_call_record_mcc"]' build/portrom/images/my_stock/etc/extension/com.oplus.app-features.xml 

#echo "ro.build.version.oplusrom=$ota_version" >> build/portrom/images/system/system/build.prop
#echo "oplus_hex_nv_id=$oplus_hex_nv_id" >> build/portrom/images/system/system/build.prop

if [[ $port_vendor_brand == "realme" ]];then
     if ensure_resource_available "devices/common/ai_memory_16.zip"; then
      unzip -o devices/common/ai_memory_16.zip -d build/portrom/images/
     fi
fi

aimemory_app=$(find build/portrom -type f -name "AIMemory.apk")

if [[ ! -f $aimemory_app ]] then
    
    if [[ $regionmark == "CN" ]];then 
        if ensure_resource_available "devices/common/ai_memory.zip"; then
            unzip -o devices/common/ai_memory.zip -d build/portrom/images/
        fi
    else
         if ensure_resource_available "devices/common/ai_memory_in/aimemory.zip"; then
            unzip -o devices/common/ai_memory_in/aimemory.zip -d build/portrom/images/
         fi
    fi
fi

for pkg in com.oplus.aimemory com.oplus.appbooster; do 
    if ! grep -q "<enable pkg=\"$pkg\"" build/portrom/images/my_product/etc/config/app_v2.xml;then
        sed -i "/<\/app>/i\  <enable pkg=\"$pkg\" priority=\"7\"/>" build/portrom/images/my_product/etc/config/app_v2.xml
    fi
done

if [[ ! -d build/portrom/images/my_product/etc/aisubsystem ]] then
     if [[ $regionmark != "CN" ]];then 
         if ensure_resource_available "devices/common/ai_memory_in/aisubsystem.zip"; then
            unzip -o devices/common/ai_memory_in/aisubsystem.zip -d build/portrom/images/
         fi
     fi
fi

if [[ -d devices/common/GTMode/overlay ]] && [[ $port_android_version != "16" ]];then
    #add_feature "oplus.software.support.gt.mode" build/portrom/images/my_product/etc/permissions/oplus.feature.android.xml
    add_feature_v2 oplus_feature "oplus.software.support.gt.mode^GT模式" 
    add_feature_v2 app_feature "com.android.settings.device_rm^Realme设备，显示GT模式需要"
    #add_feature "com.oplus.battery.support.gt_open_gamecenter" build/portrom/images/my_product/etc/extension/com.oplus.app-features.xml
    if [[ $port_vendor_brand != "realme" ]];then
        cp -rfv devices/common/GTMode/overlay/* build/portrom/images/
    fi
fi

if [[ port_vendor_brand == "realme" ]] && [[ $regionmark == "CN" ]] ;then
    add_feature_v2 oplus_feature "oplus.software.support.gt.mode^GT模式" 
    add_feature_v2 app_feature "com.android.settings.device_rm^Realme设备，显示GT模式需要"
    add_feature_v2 app_feature "com.oplus.smartsidebar.space.roulette.support^AI传送门" \
            "com.oplus.smartsidebar.space.roulette.bootreg" \ 
            "com.coloros.support_gt_boost^^args=\"boolean:true\""
    add_feature_v2 permission_oplus_feature "oplus.software.aigc_global_drag" "oplus.software.smart_loop_drag"

    #temp
    #unzip -o devices/common/glassui_rui7.zip -d build/portrom/images/
fi

#echo "ro.surface_flinger.supports_background_blur=1" >> build/portrom/images/my_product/build.prop
#echo "ro.surface_flinger.media_panel_bg_blur=1" >> build/portrom/images/my_product/build.prop

# 强光模式选项开关
add_feature_v2 oplus_feature "oplus.software.display.manual_hbm.support"
add_prop_v2 "ro.oplus.display.sell_mode.max_normal_nit" "800"

add_feature "android.hardware.biometrics.face"  build/portrom/images/my_product/etc/permissions/android.hardware.fingerprint.xml


add_feature_v2 oplus_feature "oplus.software.display.smart_color_temperature_rhythm_health_support"

#人声突显
add_feature "oplus.hardware.audio.voice_isolation_support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
add_feature "oplus.hardware.audio.voice_denoise_support" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

#旁路供电
sed -i '/<\/extend_features>/i\
    <app_feature name="com.oplus.plc_charge.support">\
        <StringList args="true"/>\
    </app_feature>' build/portrom/images/my_product/etc/extension/com.oplus.app-features-ext-bruce.xml
add_feature_v2 app_feature "com.android.settings.device_rm^Realme设备"
add_feature_v2  app_feature "com.oplus.fullscene_plc_charge.support^全场景旁路充电^args=\"boolean:true\""
#三段式
if grep -q "oplus.software.audio.alert_slider"  build/portrom/images/my_product/etc/permissions/* ;then
    add_feature "oplus.software.audio.alert_slider" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
fi

remove_feature "oplus.software.display.wcg_2.0_support" #修复切换屏幕色彩模式软重启
remove_feature "oplus.software.display.origin_roundcorner_support"
remove_feature "oplus.software.vibration_ring_mute"
remove_feature  "oplus.software.vibration_alarm_clock"
remove_feature  "oplus.software.vibration_ringtone"
remove_feature  "oplus.software.vibration_threestage_key"
remove_feature "oppo.common.support.curved.display"
remove_feature "oplus.feature.largescreen"
remove_feature "oplus.feature.largescreen.land"
remove_feature "oplus.software.audio.audioeffect_support"
remove_feature "oplus.software.audio.audiox_support"
remove_feature "oppo.breeno.three.words.support"
remove_feature "oplus.software.vibrator_qcom_lmvibrator"
remove_feature "oplus.hardware.vibrator_style_switch"
remove_feature "oplus.software.vibrator_luxunvibrator"
remove_feature "oplus.software.palmprint_non_unify"
remove_feature "oplus.software.palmprint_v1"
remove_feature "oplus.software.palmprint"
remove_feature "com.android.settings.processor_detail_gen2"
remove_feature "com.android.settings.processor_detail"
#remove_feature "os.charge.settings.batterysettings.batteryhealth"
remove_feature "oplus.software.display.adfr_v32_hp"  #OOS 小布记忆闪退

remove_feature "com.oplus.battery.phoneusage.screenon.hide"

EUICC_GOOGLE=$(find build/portrom/images/ -name "EuiccGoogle" -type d )
if [[ -d $EUICC_GOOGLE ]];then
    rm -rfv $EUICC_GOOGLE
    remove_feature "android.hardware.telephony.euicc"
    remove_feature "oplus.software.radio.esim_support_sn220u"
    remove_feature "oplus.software.radio.esim_support"
    remove_feature "com.android.systemui.keyguard_support_esimcard"
fi

cp -rf  build/baserom/images/my_product/vendor/etc/* build/portrom/images/my_product/vendor/etc/

 # Camera
 if [[ $base_android_version -lt 33 ]];then
    cp -rf  build/baserom/images/my_product/etc/camera/* build/portrom/images/my_product/etc/camera
    old_camera_app=$(find build/baserom/images/my_product -type f -name "OnePlusCamera.apk")
    if [[ -f $old_camera_app ]];then
        cp -rfv $(dirname "$old_camera_app")* build/portrom/images/my_product/priv-app/
        if [ ! -d build/portrom/images/my_product/priv-app/etc/permissions/ ];then
            mkdir -p build/portrom/images/my_product/priv-app/etc/permissions/
        fi
        rm -rf build/portrom/images/my_product/product_overlay/framework/*
        cp -rf build/baserom/images/my_product/product_overlay/* build/portrom/images/my_product/product_overlay/
    #    find build/portrom/images/ -type f -name "*.prop" -exec  sed -i "s/ro.product.model=.*/ro.product.model=${base_market_name}/g" {} \;
    #   find build/portrom/images/ -type f -name "*.prop" -exec  grep "ro.product.model" {} \;
        cp -rfv  build/baserom/images/my_product/priv-app/etc/permissions/*   build/portrom/images/my_product/priv-app/etc/permissions/
        new_camera=$(find build/portrom/images/my_product -type f -name "OplusCamera.apk")
        if [[ -f $new_camera ]]; then
            rm -rfv $(dirname $new_camera)
        fi
        base_scanner_app=$(find build/baserom/images/ -type d -name "OcrScanner")                  
        target_scanner_app=$(find build/portrom/images/ -type d -name "OcrScanner")
        if [[ -n $base_scanner_app ]] && [[ -n $target_scanner_app ]];then
                blue "替换原版扫一扫" "Replacing Stock OrcScanner"
            rm -rfv $target_scanner_app/*
            cp -rfv $base_scanner_app $target_scanner_app
        fi
    fi
else
    add_prop_v2 "ro.vendor.oplus.camera.isSupportExplorer" "1"
    base_oplus_camera_dir=$(find build/baserom/images/my_product -type d -name "OplusCamera")
    port_oplus_camera_dir=$(find build/portrom/images/my_product -type d -name "OplusCamera")

    if [[ -d "${base_oplus_camera_dir}" ]] && [[ -d "${port_oplus_camera_dir}" ]];then
        rm -rf "$port_oplus_camera_dir"/* 
        cp -rf "$base_oplus_camera_dir"/* "$port_oplus_camera_dir"/
        cp -rf build/baserom/images/my_product/product_overlay/framework/* build/portrom/images/my_product/product_overlay/framework/
    fi
 fi

if [[ ${base_device_family} == "OPSM8250" ]]; then
  camera_optimize_file=$(find build/portrom/images/ -type f -name "sys_camera_optimize_config.xml")
  # Fix wechat /alipay scan crash issue
   if [[ -f $camera_optimize_file ]]; then
      rm -f $camera_optimize_file
   fi
fi

sourceOvoiceManagerService=$(find build/baserom/images/my_product -type d -name "OVoiceManagerService")
if [[ -d "$sourceOvoiceManagerService" ]];then
    targetOvoiceManagerService=$(find build/portrom/images/my_product -type d -name "OVoiceManagerService")
    if [[ -d "$targetOvoiceManagerService" ]];then
       # rm -rfv $targetOvoiceManagerService/* 
        cp -rfv $sourceOvoiceManagerService/* $targetOvoiceManagerService/
    else
        cp -rfv $sourceOvoiceManagerService build/portrom/images/my_product/priv-app/
    fi
fi

if [[ ${base_product_device} == "OnePlus8T" ]];then 
    # Voice_trigger for OnePlus 8T
    add_feature_v2 oplus_feature "oplus.software.audio.voice_wakeup_support^旧版语音唤醒" "oplus.software.audio.voice_wakeup_3words_support"
    #add_feature "oplus.software.speechassist.oneshot.support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
    if ensure_resource_available "${work_dir}/devices/common/voice_trigger_fix.zip"; then
        unzip -o ${work_dir}/devices/common/voice_trigger_fix.zip -d ${work_dir}/build/portrom/images/
    fi
fi


cp -rf build/baserom/images/my_product/etc/Multimedia_*.xml build/portrom/images/my_product/etc/


if [[ -f "tmp/etc/permissions/multimedia_privapp-permissions-oplus.xml" ]];then
    cp -rfv tmp/etc/permissions/multimedia_*.xml build/portrom/images/my_product/etc/permissions/
fi



for file in $(find build/baserom/images/my_product/etc/ -type f -name "OVMS_*");do
    if [[ -f "$file" ]];then
        cp -rfv $file build/portrom/images/my_product/etc/
    fi
done
#fix chinese char
find build/portrom/images/config -type f -name "*file_contexts" \
	    -exec perl -i -ne 'print if /^[\x00-\x7F]+$/' {} \;
#find build/portrom/images/config -type f -name "*file_contexts" -exec sed -i -E '/[\x{4e00}-\x{9fa5}]/d' {} \;

# bootanimation
if [[ $baseIsOOS == "true" && $portIsOOS == "true" ]]; then
    rm -rf build/portrom/images/my_product/media/bootanimation
    cp -rf build/baserom/images/my_product/media/bootanimation build/portrom/images/my_product/media/
elif [[ $baseIsColorOSCN == "true" && ( $portIsColorOSGlobal == "true" || $portIsColorOS == "true" ) ]]; then
    rm -rf build/portrom/images/my_product/media/bootanimation
    cp -rf build/baserom/images/my_product/media/bootanimation build/portrom/images/my_product/media/
fi
 
rm -rf build/portrom/images/my_product/media/quickboot
cp -rf build/baserom/images/my_product/media/quickboot build/portrom/images/my_product/media/
if ensure_resource_available "devices/common/wallpaper.zip" && [[ "$portIsColorOSGlobal" == "false" ]] && [[ "$portIsOOS" == "false" ]] && [[ "$port_android_version" -lt 16 ]];then
    unzip -o devices/common/wallpaper.zip -d build/portrom/images
 fi   

rm -rf build/portrom/images/my_product/res/*
cp -rf build/baserom/images/my_product/res/* build/portrom/images/my_product/res/

#rm -rf build/portrom/images/my_product/vendor/*
cp -rf build/baserom/images/my_product/vendor/* build/portrom/images/my_product/vendor/
rm -rf  build/portrom/images/my_product/overlay/*display*[0-9]*.apk
for overlay in $(find build/baserom/images/ -type f -name "*${base_my_product_type}*".apk);do
    cp -rf $overlay build/portrom/images/my_product/overlay/
done

super_computing=$(find build/portrom/images/my_product -name "string_super_computing*")
if [[ ! -f $super_computing ]];then
    cp -rf devices/common/super_computing/* build/portrom/images/my_product/etc/
fi

baseCarrierConfigOverlay=$(find build/baserom/images/ -type f -name "CarrierConfigOverlay*.apk")
portCarrierConfigOverlay=$(find build/portrom/images/ -type f -name "CarrierConfigOverlay*.apk")
if [ -f "${baseCarrierConfigOverlay}" ] && [ -f "${portCarrierConfigOverlay}" ];then
    blue "正在替换 [CarrierConfigOverlay.apk]" "Replacing [CarrierConfigOverlay.apk]"
    rm -rf ${portCarrierConfigOverlay}
    cp -rf ${baseCarrierConfigOverlay} $(dirname ${portCarrierConfigOverlay})
else
    cp -rf ${baseCarrierConfigOverlay} build/portrom/images/my_product/overlay/
fi



#add_feature "oplus.software.display.eyeprotect_paper_texture_support" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml

add_feature "oplus.software.display.reduce_brightness_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
add_feature "oplus.software.display.reduce_brightness_rm_manual" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

add_feature "oplus.software.display.brightness_memory_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml
add_feature "oplus.software.display.sec_max_brightness_rm" build/portrom/images/my_product/etc/permissions/oplus.product.feature_multimedia_unique.xml

{
    echo "# 新增属性"
    echo "persist.lowbrightnessthreshold=0"
    echo "persist.sys.renderengine.maxLuminance=500"

    echo "ro.oplus.display.peak.brightness.duration_time=15"
    echo "ro.oplus.display.peak.brightness.effect_interval_time=1800000"
    echo "ro.oplus.display.peak.brightness.effect_times_every_day=2"
    echo "ro.display.brightness.thread.priority=true"
    echo "# 扬声器清理"
    echo "ro.oplus.audio.speaker_clean=true"
    echo "ro.vendor.oplus.radio.use_nitz_name=true"
    # Fixeme A16 crash with AndroidRuntime: 	at com.android.server.display.feature.panel.OplusFeatureDCBacklight.applyApolloDCMode(OplusFeatureDCBacklight.java:300)
    #echo "persist.brightness.apollo=1"

} >> build/portrom/images/my_product/etc/bruce/build.prop

if [[ ${base_product_device} == "OnePlus8Pro" ]] ;then 
    if [[ ${port_android_version} -gt 15 ]];then
            {
    echo "# OnePlus8Pro移除属性"
    echo "ro.display.brightness.hbm_xs="
    echo "ro.display.brightness.hbm_xs_min="
    echo "ro.display.brightness.hbm_xs_max="
    echo "ro.oplus.display.brightness.xs="
    echo "ro.oplus.display.brightness.ys="
    echo "ro.oplus.display.brightness.hbm_ys="
    echo "ro.oplus.display.brightness.default_brightness="
    echo "ro.oplus.display.brightness.normal_max_brightness="
    echo "ro.oplus.display.brightness.max_brightness="
    echo "ro.oplus.display.brightness.normal_min_brightness="
    echo "ro.oplus.display.brightness.min_light_in_dnm="
    echo "ro.oplus.display.brightness.smooth="
    echo "ro.display.brightness.mode.exp.per_20="
    echo "ro.vendor.display.AIRefreshRate.brightness="
    echo "ro.oplus.display.dwb.threshold="
    echo "ro.oplus.display.dynamic.dither="
    echo "persist.oplus.display.initskipconfig="

} >> build/portrom/images/my_product/etc/bruce/build.prop
    fi
fi

 if [[ $regionmark == "CN" ]];then
     echo "ro.oplus.display.brightness.min_settings.rm=1,1,25,4.0,0" >> build/portrom/images/my_product/etc/bruce/build.prop
 fi


if [[ -d build/baserom/images/my_product/etc/vibrator ]];then
    rm -rfv build/portrom/images/my_product/etc/vibrator
    cp -rfv build/baserom/images/my_product/etc/vibrator build/portrom/images/my_product/etc/
fi


if [[ $base_device_family == "OPSM8350" ]]; then
    if ensure_resource_available "devices/common/aon_fix_sm8350.zip"; then
        rm -rfv build/portrom/images/my_product/overlay/aon*.apk
        unzip -o devices/common/aon_fix_sm8350.zip -d build/portrom/images/
    fi

elif [[ $base_device_family == "OPSM8250" ]]; then
    if ensure_resource_available "devices/common/aon_fix_sm8250.zip"; then
        rm -rfv build/portrom/images/my_product/overlay/aon*.apk
        unzip -o devices/common/aon_fix_sm8250.zip -d build/portrom/images/
    fi
else

    sourceAONService=$(find build/baserom/images/my_product -type d -name "AONService")

    if [[ -d "$sourceAONService" ]];then
        targetAONService=$(find build/portrom/images/my_product -type d -name "AONService")
        if [[ -d "$targetAONService" ]];then
            rm -rfv $targetAONService/* 
            cp -rfv $sourceAONService/* $targetAONService/
        else
            cp -rfv $sourceAONService build/portrom/images/my_product/app/
        fi
        
        add_feature "oplus.software.aon_pay_qrcode_enable" build/portrom/images/my_product/etc/extension/com.oplus.oplus-feature.xml
        remove_feature "oplus.software.aon_sensorhub_enable" 

    fi
    if [[ ! -f build/baserom/images/my_product/overlay/aon*.apk ]] && [[ $regionmark == "CN" ]];then
        rm -rfv build/portrom/images/my_product/overlay/aon*.apk
    fi
fi
#Realme隔空手势 CN限定
if ensure_resource_available "devices/common/realme_gesture.zip" && [[ port_vendor_brand != "realme" ]] && [[ $port_android_version -lt "16" ]];then
    unzip -o devices/common/realme_gesture.zip -d build/portrom/images/
    sed -i "s/ro.camera.privileged.3rdpartyApp=.*/ro.camera.privileged.3rdpartyApp=com.aiunit.aon\;com.oplus.gesture\;/g" build/portrom/images/my_stock/build.prop
fi


if [[ "${base_product_device}" == "OnePlus9Pro" ]] ||[[ "${base_product_device}" == "OnePlus9" ]] ||  [[ "${base_product_device}" == "OP4E5D" ]] || [[ "${base_product_device}" == "OP4E3F" ]]; then
    if [[ "$portIsColorOS" == "true" ]];then
        if [[ $port_android_version -ge "15" ]];then
            if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_cos.zip"; then
                blue "ColorOS15 相机修复" "ColorOS15 Camera Fix"
                rm -rf build/portrom/images/my_product/app/OplusCamera
                rm -rf build/portrom/images/my_product/product_overlay/framework/com.oplus.camera.*.jar
                echo "ro.vendor.oplus.camera.isSupportLumo=1" >> build/portrom/images/my_product/etc/bruce/build.prop
                unzip -o devices/${base_product_device}/camera5.0-fix_cos.zip -d build/portrom/images/
                if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_odm.zip"; then
                    unzip -o devices/${base_product_device}/camera5.0-fix_odm.zip -d build/portrom/images/
                fi
            fi
        else
            blue "添加实况照片拍摄支持" "Live Photo support"
            rm -rf build/portrom/images/my_product/app/OplusCamera
            rm -rf build/portrom/images/my_product/product_overlay/framework/com.oplus.camera.*.jar
            if ensure_resource_available "devices/${base_product_device}/live_photo_adds.zip"; then
                unzip -o devices/${base_product_device}/live_photo_adds.zip -d build/portrom/images/
            fi
        fi
    elif  [[ "$portIsColorOSGlobal" == "true" ]];then
        if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_cos_global.zip"; then
            blue "ColorOS Global 15 相机修复" "ColorOS15 Global Camera Fix"
            rm -rf build/portrom/images/my_product/app/OplusCamera
            rm -rf build/portrom/images/my_product/product_overlay/framework/com.oplus.camera.*.jar
            echo "ro.vendor.oplus.camera.isSupportLumo=1" >> build/portrom/images/my_product/etc/bruce/build.prop
            unzip -o devices/${base_product_device}/camera5.0-fix_cos_global.zip -d build/portrom/images/
            if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_odm.zip"; then
                unzip -o devices/${base_product_device}/camera5.0-fix_odm.zip -d build/portrom/images/
            fi
        fi

    elif  [[ "$portIsOOS" == "true" ]];then
        if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_oos.zip"; then
            blue "OxygenOS15 相机修复" "OxygenOS 15 Camera Fix"
            rm -rf build/portrom/images/my_product/app/OplusCamera
            rm -rf build/portrom/images/my_product/product_overlay/framework/com.oplus.camera.*.jar
            echo "ro.vendor.oplus.camera.isSupportLumo=1" >> build/portrom/images/my_product/etc/bruce/build.prop
            unzip -o devices/${base_product_device}/camera5.0-fix_oos.zip -d build/portrom/images/
            if ensure_resource_available "devices/${base_product_device}/camera5.0-fix_odm.zip"; then
                unzip -o devices/${base_product_device}/camera5.0-fix_odm.zip -d build/portrom/images/
            fi
        fi
    fi
fi
#高能户外模式
add_prop_v2 "ro.oplus.ridermode.support_feature_switch" "11"

#解锁朋友圈动态图
cp -rf build/portrom/images/system_ext/etc/Multimedia_Daemon_List.xml  tmp/

xmlstarlet ed -u '//wechat-livephoto/name[text()="com.tencent.mm"]/following-sibling::attribute[1]' -v "all" tmp/Multimedia_Daemon_List.xml > build/portrom/images/system_ext/etc/Multimedia_Daemon_List.xml

# Fix atfwd@2.0.policy 
atfwd_policy_file=$(find build/portrom/images/vendor/ -name "atfwd@2.0.policy" -print -quit)

if [ -n "$atfwd_policy_file" ]; then
  echo "Found policy file: $atfwd_policy_file"
  for prop in getid gettid setpriority; do
    if ! grep -q "${prop}: 1" "$atfwd_policy_file"; then
      echo "${prop}: 1" >> "$atfwd_policy_file"
    else
      blue "⚙️  Already contains ${prop}: 1"
    fi
  done
else
  blue "❌ No atfwd@2.0.policy found."
fi

if  [[ "${base_product_device}" == "OnePlus9Pro" ]] ||[[ "${base_product_device}" == "OnePlus9" ]];then
    echo -e "\n[FeatureTorch]\n    isSupportTorchStrengthLevel = TRUE\n    maxStrengthLevel = 4\n    defaultStrengthLevel = 4\n " >> build/portrom/images/odm/etc/camera/CameraHWConfiguration.config
fi

if [[ ${port_android_version} == 16 ]] && [[ ${base_android_version} -lt 15 ]];then
    rm -rf build/portrom/images/system_ext/priv-app/com.qualcomm.location
    #remove_feature "oplus.software.display.dcbacklight_support" force
if ensure_resource_available "devices/common/nfc_fix_a16_v2.zip"; then
    rm -rf build/portrom/images/system/system/priv-app/NfcNci/*
    unzip -o devices/common/nfc_fix_a16_v2.zip -d ${work_dir}/build/portrom/images/
fi
    if ensure_resource_available "devices/common/wifi_fix_a16.zip" && [[ $regionmark == "CN" ]];then
    unzip -o devices/common/wifi_fix_a16.zip -d ${work_dir}/build/portrom/images/
    rm -rf build/portrom/images/system/system/apex/com.google.android.wifi*.apex
    fi
    if [[ ${port_oplusrom_version} == "16.0.1" ]] && [[ $regionmark != "CN" ]] ;then
        if ensure_resource_available "devices/common/oos_1601_fix.zip"; then
            unzip -o devices/common/oos_1601_fix.zip -d build/portrom/images/
        fi
    fi

    if [[ -f build/portrom/images/my_product/cust/CN/etc/power_profile/power_profile.xml ]];then
        cp -rf build/portrom/images/odm/etc/power_profile/power_profile.xml build/portrom/images/my_product/cust/CN/etc/power_profile/
    fi

    #camera fix
    echo "vendor.audio.c2.preferred=true" >> build/portrom/images/vendor/build.prop
    echo "vendor.audio.hdr.record.enable=false" >> build/portrom/images/vendor/build.prop
    if [[ $base_product_device == "OP4E3F" ]];then
        # Fix Find X3 Pro brightness
        sed -i "/ro.oplus.display.brightness.apollo*/d" build/portrom/images/my_product/build.prop
        sed -i "/persist.brightness.apollo/d" build/portrom/images/my_product/build.prop
        rm -rf build/portrom/images/my_product/vendor/etc/display_apollo_list.xml
    fi
fi

if ensure_resource_available "devices/common/hdr_fix.zip" && [[ $base_android_version -le 14 ]];then
    unzip -o devices/common/hdr_fix.zip -d build/portrom/images/
    echo "persist.sys.feature.uhdr.support=true" >> build/portrom/images/my_product/etc/bruce/build.prop
fi


#自定义替换


#Devices/机型代码/overlay 按照镜像的目录结构，可直接替换目标。

if [[ -d "devices/common/overlay" ]]; then
    cp -rfv  devices/common/overlay/* build/portrom/images/
fi

if [[ -d "devices/${base_product_device}/overlay" ]]; then
    cp -rfv  devices/${base_product_device}/overlay/* build/portrom/images/
else
    yellow "devices/${base_product_device}/overlay 未找到" "devices/${base_product_device}/overlay not found" 
fi

if ensure_resource_available "devices/${base_product_device}/odm_selinux_fix_a16.zip" && [[ $port_android_version == 16 ]]; then
    unzip -o devices/${base_product_device}/odm_selinux_fix_a16.zip -d ${work_dir}/build/portrom/images/
fi

for zip in $(find devices/${base_product_device}/ -name "*.zip"); do
    if unzip -l $zip | grep -q "anykernel.sh" ;then
        blue "检查到第三方内核压缩包 $zip [AnyKernel类型]" "Custom Kernel zip $zip detected [Anykernel]"
        if echo $zip | grep -q ".*-KSU" ; then
          unzip $zip -d tmp/anykernel-ksu/ > /dev/null 2>&1
        elif echo $zip | grep -q ".*-NoKSU" ; then
          unzip $zip -d tmp/anykernel-noksu/ > /dev/null 2>&1
        else
          unzip $zip -d tmp/anykernel/ > /dev/null 2>&1
        fi
    fi
done
for anykernel_dir in tmp/anykernel*; do
    if [ -d "$anykernel_dir" ]; then
        blue "开始整合第三方内核进boot.img" "Start integrating custom kernel into boot.img"
        kernel_file=$(find "$anykernel_dir" -name "Image" -exec readlink -f {} +)
        dtb_file=$(find "$anykernel_dir" -name "dtb" -exec readlink -f {} +)
        dtbo_img=$(find "$anykernel_dir" -name "dtbo.img" -exec readlink -f {} +)
        if [[ "$anykernel_dir" == *"-ksu"* ]]; then
            [[ -f $dtbo_img ]] && cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_ksu.img
            patch_kernel "$kernel_file" "$dtb_file" "boot_ksu.img"
            blue "生成内核boot_boot_ksu.img完毕" "New boot_ksu.img generated"
        elif [[ "$anykernel_dir" == *"-noksu"* ]]; then
            cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_noksu.img
            patch_kernel "$kernel_file" "$dtb_file" "boot_noksu.img"
            blue "生成内核boot_noksu.img" "New boot_noksu.img generated"
        else
            cp $dtbo_img ${work_dir}/devices/$base_product_device/dtbo_custom.img
            patch_kernel "$kernel_file" "$dtb_file" "boot_custom.img"
            blue "生成内核boot_custom.img完毕" "New boot_custom.img generated"
        fi
    fi
    rm -rf $anykernel_dir
done


while IFS= read -r prop; do
    val=$(grep -E '^ro.build.kernel.id=' "$prop" | cut -d= -f2)
    if [ -n "$val" ]; then
        kernel_id="$val"
        kernel_prop="$prop"
        break
    fi
done < <(find "$work_dir/build/portrom/images" -type f -name "build.prop")

kernel_major=$(echo "$kernel_id" | grep -Eo '^[0-9]+\.[0-9]+')

kmi=""
case "$kernel_major" in
    6.1)  kmi="android14-6.1" ;;
    6.6)  kmi="android15-6.6" ;;
    6.12) kmi="android16-6.12" ;;
esac

if [ -z "$kmi" ]; then
    echo "⚠ 未匹配到 KMI（ro.build.kernel.id=$kernel_id），跳过 ksud 修补 init_boot"
else
    echo "✔ 检测到内核版本 $kernel_major → 使用 KMI: $kmi"
    mkdir -p tmp/init_boot
    cd tmp/init_boot
    cp -f ${work_dir}/build/baserom/images/init_boot.img ${work_dir}/tmp/init_boot
    ksud boot-patch \
        -b "${work_dir}/tmp/init_boot/init_boot.img" \
        --magiskboot magiskboot \
        --kmi "$kmi"
    mv -f ${work_dir}/tmp/init_boot/kernelsu_*.img ${work_dir}/build/baserom/images/init_boot-kernelsu.img
    cd $work_dir
fi

#添加erofs文件系统fstab
# if [ ${pack_type} == "EROFS" ];then
#     yellow "检查 vendor fstab.qcom是否需要添加erofs挂载点" "Validating whether adding erofs mount points is needed."
#     if ! grep -q "erofs" build/portrom/images/vendor/etc/fstab.qcom ; then
#                for pname in system odm vendor product mi_ext system_ext; do
#                      sed -i "/\/${pname}[[:space:]]\+ext4/{p;s/ext4/erofs/;s/ro,barrier=1,discard/ro/;}" build/portrom/images/vendor/etc/fstab.qcom
#                      added_line=$(sed -n "/\/${pname}[[:space:]]\+erofs/p" build/portrom/images/vendor/etc/fstab.qcom)
#                     if [ -n "$added_line" ]; then
#                         yellow "添加$pname" "Adding mount point $pname"
#                     else
#                         error "添加失败，请检查" "Adding faild, please check."
#                         exit 1
                        
#                     fi
#                 done
#     fi
# fi

# data 加密
remove_data_encrypt=$(grep "remove_data_encryption" bin/port_config |cut -d '=' -f 2)
if [[ ${remove_data_encrypt} == "true" ]];then
    DECRYPTRD="-DECRYPTED"
    blue "去除data加密"
    for fstab in $(find build/portrom/images -type f -name "fstab.*");do
		blue "Target: $fstab"
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2+emmc_optimized+wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:aes-256-cts:v2//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts:wrappedkey_v0//g" $fstab
		sed -i "s/,metadata_encryption=aes-256-xts//g" $fstab
		sed -i "s/,fileencryption=aes-256-xts//g" $fstab
        sed -i "s/,fileencryption=ice//g" $fstab
		sed -i "s/fileencryption/encryptable/g" $fstab
	done
fi

# for pname in ${port_partition};do
#     rm -rf build/portrom/images/${pname}.img
# done
echo "${pack_type}">fstype.txt
if [[ $super_extended == true ]];then
    superSize=$(bash bin/getSuperSize.sh "others")
elif [[ $base_product_model == "KB2000" ]] && [[ "$is_ab_device" == false ]] ; then
    # OnePlus 8T A-only ROM
    echo ro.product.cpuinfo=SM8250 >> build/portrom/images/my_manifest/build.prop
    superSize=$(bash bin/getSuperSize.sh OnePlus9R)
elif [[ $base_product_model == "LE2101" ]]; then
    # "9R IN"
    superSize=$(bash bin/getSuperSize.sh OnePlus8T)
else
    superSize=$(bash bin/getSuperSize.sh $base_product_device)
fi

green "Super大小为${superSize}" "Super image size: ${superSize}"
green "开始打包镜像" "Packing img"
for pname in ${super_list};do
    if [ -d "build/portrom/images/$pname" ];then
        if [[ "$OSTYPE" == "darwin"* ]];then
            thisSize=$(find build/portrom/images/${pname} | xargs stat -f%z | awk ' {s+=$1} END { print s }' )
        else
            thisSize=$(du -sb build/portrom/images/${pname} |tr -cd 0-9)
        fi
        blue 以[$pack_type]文件系统打包[${pname}.img] "Packing [${pname}.img] with [$pack_type] filesystem"
        python3 bin/fspatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_fs_config
        python3 bin/contextpatch.py build/portrom/images/${pname} build/portrom/images/config/${pname}_file_contexts
        #perl -pi -e 's/\\@/@/g' build/portrom/images/config/${pname}_file_contexts
        mkfs.erofs -zlz4hc,9 --mount-point ${pname} --fs-config-file build/portrom/images/config/${pname}_fs_config --file-contexts build/portrom/images/config/${pname}_file_contexts -T 1648635685 build/portrom/images/${pname}.img build/portrom/images/${pname}
        if [ -f "build/portrom/images/${pname}.img" ];then
            green "成功以 [erofs] 文件系统打包 [${pname}.img]" "Packing [${pname}.img] successfully with [erofs] format"
            #rm -rf build/portrom/images/${pname}
        else
            error "以 [${pack_type}] 文件系统打包 [${pname}] 分区失败" "Faield to pack [${pname}]"
            exit 1
        fi
        unset fsType
        unset thisSize
    fi
done


rm fstype.txt

if [[ ${port_vendor_brand} == "realme" ]];then
    os_type="RealmeUI"
else
    os_type="ColorOS"
fi
rom_version=$(cat build/portrom/images/my_manifest/build.prop | grep "ro.build.display.id=" |  awk 'NR==1' | cut -d "=" -f2 | cut -d "(" -f1)
for img in $(find build/baserom/ -type f -name "vbmeta*.img");do
    blue "vbmeta验证禁用： $img" "Disable vbmeta verify: $img"
    python3 bin/patch-vbmeta.py ${img} > /dev/null 2>&1
done
if [[ -f devices/${base_product_device}/recovery.img ]]; then
  cp -rfv devices/${base_product_device}/recovery.img build/baserom/images/
fi

if [[ -f devices/${base_product_device}/vendor_boot.img ]]; then
  cp -rfv devices/${base_product_device}/vendor_boot.img build/baserom/images/
fi

if [[ -f devices/${base_product_device}/abl.img ]]; then
  cp -rfv devices/${base_product_device}/abl.img build/portrom/images/
fi

if [[ -f devices/${base_product_device}/odm.img ]]; then
  cp -rfv devices/${base_product_device}/odm.img build/portrom/images/
fi

if [[ -f devices/${base_product_device}/tz.img ]]; then
  cp -rfv devices/${base_product_device}/tz.img build/baserom/images/
fi

if [[ -f devices/${base_product_device}/keymaster.img ]]; then
  cp -rfv devices/${base_product_device}/keymaster.img build/baserom/images/
fi

if [[ $is_ab_device == true ]]; then
    if [[ ! -f build/portrom/images/my_preload.img ]];then
        cp -rfv devices/common/my_preload_empty.img build/portrom/images/my_preload.img
    fi
    if [[ ! -f build/portrom/images/my_company.img ]];then
        cp -rfv devices/common/my_company_empty.img build/portrom/images/my_company.img
    fi
elif [[ $is_ab_device == false ]];then
    rm -rf build/portrom/images/my_company.img
    rm -rf build/portrom/images/my_preload.img
fi

pack_timestamp=$(date +"%m%d%H%M")
if [[ $pack_method == "stock" ]];then
    rm -rf out/target/product/${base_product_device}/
    mkdir -p out/target/product/${base_product_device}/IMAGES
    mkdir -p out/target/product/${base_product_device}/META
    for part in SYSTEM SYSTEM_EXT PRODUCT VENDOR MY_MANIFEST; do
        mkdir -p out/target/product/${base_product_device}/$part
    done
    mv -fv build/portrom/images/*.img out/target/product/${base_product_device}/IMAGES/
    if [[ -d build/baserom/firmware-update ]];then
        bootimg=$(find build/baserom/ -name "boot.img")
        cp -rf $bootimg out/target/product/${base_product_device}/IMAGES/
    else
        if [[ -f build/baserom/images/init_boot-kernelsu.img ]];then
            mv build/baserom/images/init_boot-kernelsu.img build/baserom/images/init_boot.img
        fi
        mv -fv build/baserom/images/*.img out/target/product/${base_product_device}/IMAGES/
    fi

    if [[ -d devices/${base_product_device} ]];then

        ksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_ksu.img")
        dtbo_file=$(find devices/$base_product_device/ -type f -name "*dtbo_ksu.img")
        if [ -n "$ksu_bootimg_file" ];then
            mv -fv $ksu_bootimg_file out/target/product/${base_product_device}/IMAGES/boot.img
            mv -fv $dtbo_file out/target/product/${base_product_device}/IMAGES/dtbo.img
        else
            spoof_bootimg out/target/product/${base_product_device}/IMAGES/boot.img
        fi
    fi
    rm -rf out/target/product/${base_product_device}/META/ab_partitions.txt
    rm -rf out/target/product/${base_product_device}/META/update_engine_config.txt
    rm -rf out/target/product/${base_product_device}/target-file.zip
    for part in out/target/product/${base_product_device}/IMAGES/*.img; do
        partname=$(basename "$part" .img)
        echo $partname >> out/target/product/${base_product_device}/META/ab_partitions.txt
        if echo $super_list | grep -q -w "$partname"; then
            super_list_info+="$partname "
            otatools/bin/map_file_generator $part ${part%.*}.map
        fi
    done 
    rm -rf out/target/product/${base_product_device}/META/dynamic_partitions_info.txt
    let groupSize=superSize-1048576
    {
        echo "super_partition_size=$superSize"
        echo "super_partition_groups=qti_dynamic_partitions"
        echo "super_qti_dynamic_partitions_group_size=$groupSize"
        echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
        echo "virtual_ab=true"
        echo "virtual_ab_compression=true"
    } >> out/target/product/${base_product_device}/META/dynamic_partitions_info.txt

    {
        echo "default_system_dev_certificate=key/testkey"
        echo "recovery_api_version=3"
        echo "fstab_version=2"
        echo "ab_update=true"
     } >> out/target/product/${base_product_device}/META/misc_info.txt
    
    {
        echo "PAYLOAD_MAJOR_VERSION=2"
        echo "PAYLOAD_MINOR_VERSION=8"
    } >> out/target/product/${base_product_device}/META/update_engine_config.txt

    if [[ "$is_ab_device" == false ]];then
        sed -i "/ab_update=true/d" out/target/product/${base_product_device}/META/misc_info.txt
        {
            echo "blockimgdiff_versions=3,4"
            echo "use_dynamic_partitions=true"
            echo "dynamic_partition_list=$super_list_info"
            echo "super_partition_groups=qti_dynamic_partitions"
            echo "super_qti_dynamic_partitions_group_size=$superSize"
            echo "super_qti_dynamic_partitions_partition_list=$super_list_info"
            echo "board_uses_vendorimage=true"
            echo "cache_size=402653184"

        } >> out/target/product/${base_product_device}/META/misc_info.txt
        mkdir -p out/target/product/${base_product_device}/OTA/bin
        for part in MY_PRODUCT MY_BIGBALL MY_CARRIER MY_ENGINEERING MY_HEYTAP MY_MANIFEST MY_REGION MY_STOCK;do
            mkdir -p out/target/product/${base_product_device}/$part
        done

        if [[ -f devices/${base_product_device}/OTA/bin/updater ]];then
            cp -rf devices/${base_product_device}/OTA/bin/updater out/target/product/${base_product_device}/OTA/bin
        else
            cp -rf devices/common/non-ab/OTA/updater out/target/product/${base_product_device}/OTA/bin
        fi
        if [[ -d build/baserom/firmware-update ]];then
            cp -rf build/baserom/firmware-update out/target/product/${base_product_device}/
        elif find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \) | grep -q .; then
            for firmware in $(find build/baserom/ -type f \( -name "*.elf" -o -name "*.mdn" -o -name "*.bin" \));do
                mv  -rfv $firmware out/target/product/${base_product_device}/firmware-update
            done
            bootimg=$(find build/baserom/ -name "boot.img")
            dtboimg=$(find build/baserom/images -name "dtbo.img")
            vbmetaimg=$(find build/baserom/ -name "vbmeta.img")
            vmbeta_systemimg=$(find build/baserom/ -name "vbmeta_sytem.img")
            cp -rf $bootimg out/target/product/${base_product_device}/IMAGES/
            cp -rf $dtboimg out/target/product/${base_product_device}/firmware-update
            cp -rf $vbmetaimg out/target/product/${base_product_device}/firmware-update
            cp -rf $vmbeta_systemimg out/target/product/${base_product_device}/firmware-update
        fi

        if [[ -d build/baserom/storage-fw ]];then
            cp -rf build/baserom/storage-fw out/target/product/${base_product_device}/
            cp -rf build/baserom/ffu_tool out/target/product/${base_product_device}/storage-fw
        else
            cp -rf build/baserom/ffu_tool out/target/product/${base_product_device}/
	fi

        export OUT=$(pwd)/out/target/product/${base_product_device}/
        if [[ -f devices/${base_product_device}/releasetools.py ]];then
            cp -rf devices/${base_product_device}/releasetools.py out/target/product/${base_product_device}/META/
        else
            cp -rf devices/common/releasetools.py out/target/product/${base_product_device}/META/
        fi

        mkdir -p out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        if [[ -f devices/${base_product_device}/recovery.fstab ]];then
            cp -rf devices/${base_product_device}/recovery.fstab out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        else
            cp -rf devices/common/recovery.fstab out/target/product/${base_product_device}/RECOVERY/RAMDISK/etc/
        fi
    fi
    declare -A prop_paths=(
    ["system"]="SYSTEM"
    ["product"]="PRODUCT"
    ["system_ext"]="SYSTEM_EXT"
    ["vendor"]="VENDOR"
    ["my_manifest"]="MY_MANIFEST"
    )

    for dir in "${!prop_paths[@]}"; do
        prop_file=$(find "build/portrom/images/$dir" -type f -name "build.prop" -not -path "*/system_dlkm/*" -not -path "*/odm_dlkm/*" -print -quit)
        
        if [ -n "$prop_file" ]; then
            target_dir="out/target/product/${base_product_device}/${prop_paths[$dir]}"
            if [ ! -d "$target_dir" ]; then
                mkdir -p "$target_dir"
            fi
            cp "$prop_file" "$target_dir/"
        fi
    done
    target_folder=${rom_version#*_}
    pushd otatools
    export PATH=$(pwd)/bin/:$PATH
    mkdir -p ${work_dir}/out/$target_folder
    ./bin/ota_from_target_files --partial= --force_minor_version 9 ${work_dir}/out/target/product/${base_product_device}/ ${work_dir}/out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip
    popd
    ziphash=$(md5sum out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip |head -c 10)
    mv -f out/${base_product_device}-ota_full-${port_rom_version}-user-${port_android_version}.0.zip out/$target_folder/ota_full-${rom_version}-${port_product_model}-${pack_timestamp}-$regionmark-${portrom_version_security_patch}-${ziphash}.zip
	blue "打包完成： out/$target_folder/ota_full-${rom_version}-${port_product_model}-${pack_timestamp}-$regionmark-${portrom_version_security_patch}-${ziphash}.zip"
else
   if [[ $is_ab_device == true ]]; then
        # 打包 super.img
        blue "打包V-A/B机型 super.img" "Packing super.img for V-AB device"
        lpargs="-F --virtual-ab --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 3 --device super:$superSize --group=qti_dynamic_partitions_a:$superSize --group=qti_dynamic_partitions_b:$superSize"

        for pname in ${super_list};do
            if [ -f "build/portrom/images/${pname}.img" ];then
                subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
                green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
                args="--partition ${pname}_a:none:${subsize}:qti_dynamic_partitions_a --image ${pname}_a=build/portrom/images/${pname}.img --partition ${pname}_b:none:0:qti_dynamic_partitions_b"
                lpargs="$lpargs $args"
                unset subsize
                unset args
            fi
        done
    else
        blue "打包A-only super.img" "Packing super.img for A-only device"
        lpargs="-F --output build/portrom/images/super.img --metadata-size 65536 --super-name super --metadata-slots 2 --block-size 4096 --device super:$superSize --group=qti_dynamic_partitions:$superSize"
        for pname in ${super_list};do
            if [ -f "build/portrom/images/${pname}.img" ];then
                if [[ "$OSTYPE" == "darwin"* ]];then
                subsize=$(find build/portrom/images/${pname}.img | xargs stat -f%z | awk ' {s+=$1} END { print s }')
                else
                    subsize=$(du -sb build/portrom/images/${pname}.img |tr -cd 0-9)
                fi
                green "Super 子分区 [$pname] 大小 [$subsize]" "Super sub-partition [$pname] size: [$subsize]"
                args="--partition ${pname}:none:${subsize}:qti_dynamic_partitions --image ${pname}=build/portrom/images/${pname}.img"
                lpargs="$lpargs $args"
                unset subsize
                unset args
            fi
        done
    fi
    lpmake $lpargs
    if [ -f "build/portrom/images/super.img" ];then
        green "成功打包 super.img" "Pakcing super.img done."
    else
        error "无法打包 super.img"  "Unable to pack super.img."
        exit 1
    fi
    #for pname in ${super_list};do
    #    rm -rf build/portrom/images/${pname}.img
    #done


    blue "正在压缩 super.img" "Comprising super.img"
    zstd build/portrom/images/super.img -o build/portrom/super.zst

    blue "正在生成刷机脚本" "Generating flashing script"

    mkdir -p out/${os_type}_${rom_version}/META-INF/com/google/android/   
    mkdir -p out/${os_type}_${rom_version}/firmware-update
    mkdir -p out/${os_type}_${rom_version}/bin/windows/
    cp -rf bin/flash/platform-tools-windows/* out/${os_type}_${rom_version}/bin/windows/
    cp -rf bin/flash/windows_flash_script.bat out/${os_type}_${rom_version}/
    cp -rf bin/flash/mac_linux_flash_script.sh out/${os_type}_${rom_version}/
    cp -rf bin/flash/zstd out/${os_type}_${rom_version}/META-INF/
    mv -f build/portrom/*.zst out/${os_type}_${rom_version}/
    if [[ -f devices/${base_product_device}/update-binary ]];then
        cp -rf devices/${base_product_device}/update-binary out/${os_type}_${rom_version}/META-INF/com/google/android/
    else
        cp -rf bin/flash/update-binary out/${os_type}_${rom_version}/META-INF/com/google/android/
    fi
    if [[ $is_ab_device = "false" ]];then
        mv -f build/baserom/firmware-update/*.img out/${os_type}_${rom_version}/firmware-update
        for fwimg in $(ls out/${os_type}_${rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"xbl"* ]] || [[ $fwimg == *"dtbo"* ]] ;then
                # Warning: If wrong xbl img has been flashed, it will cause phone hard brick, so we just skip it with fastboot mode.
                continue

            elif [[ ${fwimg} == "BTFM" ]];then
                part="bluetooth"
            elif [[ ${fwimg} == "cdt_engineering" ]];then
                part="engineering_cdt"
            elif [[ ${fwimg} == "BTFM" ]];then
                part="bluetooth"
            elif [[ ${fwimg} == "dspso" ]];then
                part="dsp"
            elif [[ ${fwimg} == "keymaster64" ]];then
                part="keymaster"
            elif [[ ${fwimg} == "qupv3fw" ]];then
                part="qupfw"
            elif [[ ${fwimg} == "static_nvbk" ]];then
                part="static_nvbk"
            else
                part=${fwimg}                
            fi

            sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${part}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
            sed -i "/# firmware/a fasatboot flash "${part}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        done
        sed -i "/_b/d" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/_a//g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i '/^REM SET_ACTION_SLOT_A_BEGIN/,/^REM SET_ACTION_SLOT_A_END/d' out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i '/# SET_ACTION_SLOT_A_BEGIN/,/# SET_ACTION_SLOT_A_END/d' out/${os_type}_${rom_version}/mac_linux_flash_script.sh
    else
        mv -f build/baserom/images/*.img out/${os_type}_${rom_version}/firmware-update
        for fwimg in $(ls out/${os_type}_${rom_version}/firmware-update |cut -d "." -f 1 |grep -vE "super|cust|preloader");do
            if [[ $fwimg == *"xbl"* ]] || [[ $fwimg == *"dtbo"* ]] || [[ $fwimg == *"reserve"* ]] || [[ $fwimg == *"boot"* ]];then
                rm -rfv out/${os_type}_${rom_version}/firmware-update/*reserve*
                # Warning: If wrong xbl img has been flashed, it will cause phone hard brick, so we just skip it with fastboot mode.
                continue
            elif [[ $fwimg == "mdm_oem_stanvbk" ]] || [[ $fwimg == "spunvm" ]] ;then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/\# firmware/a fastboot flash "${fwimg}" firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
            elif [ "$(echo ${fwimg} |grep vbmeta)" != "" ];then
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe --disable-verity --disable-verification flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/\# firmware/a fastboot --disable-verity --disable-verification flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
                sed -i "/\# firmware/a fastboot --disable-verity --disable-verification flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
            else
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/REM firmware/a \\\bin\\\windows\\\fastboot.exe flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/windows_flash_script.bat
                sed -i "/\# firmware/a fastboot flash "${fwimg}"_b firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
                sed -i "/\# firmware/a fastboot flash "${fwimg}"_a firmware-update\/"${fwimg}".img" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
            fi
        done
    fi

    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/windows_flash_script.bat
    sed -i "s/REGIONMARK/${regionmark}/g" out/${os_type}_${rom_version}/windows_flash_script.bat
    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
    sed -i "s/REGIONMARK/${regionmark}/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/REGIONMARK/${regionmark}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/portversion/${port_rom_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/baseversion/${base_rom_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/andVersion/${port_android_version}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
    sed -i "s/device_code/${base_product_device}/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary

    unix2dos out/${os_type}_${rom_version}/windows_flash_script.bat

    #disable vbmeta
    for img in $(find out/${os_type}_${rom_version}/ -type f -name "vbmeta*.img");do
        blue "vbmeta验证禁用： $img" "Disable vbmeta verify: $img"
        python3 bin/patch-vbmeta.py ${img}
    done

    ksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_ksu.img")
    nonksu_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_noksu.img")
    custom_bootimg_file=$(find devices/$base_product_device/ -type f -name "*boot_custom.img")

    if [[ -f $nonksu_bootimg_file ]];then
        nonksubootimg=$(basename "$nonksu_bootimg_file")
        mv -f $nonksu_bootimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_noksu.img out/${os_type}_${rom_version}/firmware-update/dtbo_noksu.img
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_official.img/$nonksubootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo.img/dtbo_noksu.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i '/^REM OFFICAL_BOOT_START/,/^REM OFFICAL_BOOT_END/d' out/${os_type}_${rom_version}/windows_flash_script.bat
    else
        bootimg=$(find build/baserom/ out/${os_type}_${rom_version} -name "boot.img")
        mv -f $bootimg out/${os_type}_${rom_version}/boot_official.img
    fi

    if [[ -f "$ksu_bootimg_file" ]];then
        ksubootimg=$(basename "$ksu_bootimg_file")
        mv -f $ksu_bootimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_ksu.img out/${os_type}_${rom_version}/firmware-update/dtbo_ksu.img
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$ksubootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_ksu.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i '/^REM OFFICAL_BOOT_START/,/^REM OFFICAL_BOOT_END/d' out/${os_type}_${rom_version}/windows_flash_script.bat
        
    elif [[ -f "$custom_bootimg_file" ]];then
        custombootimg=$(basename "$custom_botimg_file")
        mv -f $custom_botimg_file out/${os_type}_${rom_version}/
        mv -f  devices/$base_product_device/dtbo_custom.img out/${os_type}_${rom_version}/firmware-update/dtbo_custom.img
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/boot_tv.img/$custombootimg/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/META-INF/com/google/android/update-binary
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/windows_flash_script.bat
        sed -i "s/dtbo_tv.img/dtbo_custom.img/g" out/${os_type}_${rom_version}/mac_linux_flash_script.sh
        
    fi

    find out/${os_type}_${rom_version} |xargs touch
    pushd out/${os_type}_${rom_version}/ >/dev/null || exit
    zip -r ${os_type}_${rom_version}.zip ./*
    mv ${os_type}_${rom_version}.zip ../
    popd >/dev/null || exit
    pack_timestamp=$(date +"%m%d%H%M")
    hash=$(md5sum out/${os_type}_${rom_version}.zip |head -c 10)
    if [[ $pack_type == "EROFS" ]] && [[ -f out/${os_type}_${rom_version}/$ksubootimg ]];then
        pack_type="ROOT_"${pack_type}
    fi
    mv out/${os_type}_${rom_version}.zip out/${os_type}_${rom_version}_${hash}_${port_product_model}_${pack_timestamp}_${pack_type}.zip
    green "移植完毕" "Porting completed"    
    green "输出包路径：" "Output: "
    green "$(pwd)/out/${os_type}_${rom_version}_${hash}_${port_product_model}_${pack_timestamp}_${pack_type}.zip"
fi
