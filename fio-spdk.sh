#!/bin/bash

usage="invalid parameters provided. \nexample:\n\t $0 [-t nvme|spdk] -d \"nvme0n1 nvme1n1\" [-b \"0-7 8-15\"]\n"

export my_dir="$( cd "$( dirname "$0"  )" && pwd  )"
timestamp=`date +%Y%m%d_%H%M%S`
output_dir=${my_dir}/${timestamp}

# default values
type=nvme
disks=""
bind_list=""

while getopts "t:d:b:" opt
do
    case $opt in 
    t)
        type=$OPTARG
        ;;
    d)
        disks=($OPTARG)
        ;;
    b)
        bind_list=($OPTARG)
        ;;
    *)
        echo -e ${usage}
        exit 1
    esac
done

if [[ "${type}" != "spdk" ]] && [[ "${type}" != "nvme" ]]
then
    echo -e ${usage}
    exit 1
fi

if [ -z "${disks}" ]
then
    echo -e ${usage}
    exit 1
fi

source ${my_dir}/functions
source ${my_dir}/job_config
source ${my_dir}/func_spdk
source ${my_dir}/nvme_dev.sh > /dev/null

centos_ver=$(get_centos_version)
if [[ "${centos_ver}" != "7" ]] && [[ "${centos_ver}" != "8" ]]
then
    echo "unsupported operating system, please use either centos7 or centos8"
    exit 3;
fi

spdk_dir="${my_dir}/centos${centos_ver}/spdk"
fio_dir="${my_dir}/centos${centos_ver}/fio"
fio_cmd="${fio_dir}/fio"
ld_preload=""
filename_format="/dev/%s"
nvme_dev_info=$(${my_dir}/nvme_dev.sh)

if [ ! -d "${output_dir}" ]; then mkdir -p ${output_dir}; fi
result_dir=${output_dir}/result
drvinfo_dir=${output_dir}/drvinfo
iolog_dir=${output_dir}/io_logs
mkdir -p ${result_dir}
mkdir -p ${drvinfo_dir}
mkdir -p ${iolog_dir}

echo -e "$0 $@\n"        > ${output_dir}/sysinfo.log
echo "${nvme_dev_info}" >> ${output_dir}/sysinfo.log
collect_sys_info        >> ${output_dir}/sysinfo.log

if [ "${type}" == "spdk" ]
then
    # prepare spdk environment
    spdk_while_list=""
    spdk_disks=""
    for disk in ${disks[@]}
    do
        spdk_while_list="${spdk_while_list} $(nvme2busid_full ${disk})"
        spdk_disks=(${spdk_disks[@]} $(nvme2busid_spdk ${disk}))
    done
    
    setup_spdk "${spdk_dir}" "${spdk_while_list}"
    if [ $? -ne 0 ]
    then
        echo "setup spdk failed, revert ..."
        reset_spdk "${spdk_dir}"
        echo "revert done"
        exit 2
    fi
    ld_preload="${spdk_dir}/build/fio/spdk_nvme "
    filename_format="trtype=PCIe traddr=%s ns=1 "
    disks=(${spdk_disks[@]})
    export ioengine=spdk
    echo "start fio test using spdk"
else
    echo "start fio test using conventional nvme device"
fi

bind_cnt=0
if [ ! -z ${bind_list} ]
then
    bind_cnt=${#bind_list[@]}
fi

for workload in ${workloads[@]}
do
    fio_pid_list=""
    i=0
    for disk in ${disks[@]};
    do
        bind_param=""
        if [ $i -lt $bind_cnt ]
        then
            bind_param="${bind_opt}=${bind_list[$i]}"
        fi
        export output_name=${iolog_dir}/${disk}_${workload}
        
        # echo ${filename_format} ${disk}
        # echo $(printf "${filename_format}\n" ${disk})

        LD_PRELOAD=${ld_preload} \
        ${fio_cmd} --filename="$(printf "${filename_format}" ${disk})" \
            ${bind_param} \
            --output=${result_dir}/${disk}_${workload}.fio \
            ${my_dir}/jobs/${workload}.fio &
        fio_pid_list="${fio_pid_list} $!"
        i=$(($i+1))
    done

    wait ${fio_pid_list}
    sync
done

reset_spdk "${spdk_dir}"

for disk in ${disks[@]}
do
    fio_to_csv ${result_dir} ${disk}
done

consolidate_summary ${result_dir} ${output_dir}