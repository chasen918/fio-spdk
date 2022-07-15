#!/bin/bash
#
# lspci -d1e3b: -v | grep -e NUMA -e Non-Vol | sed -r -e "s/(.*)\s+Non-Vol.*/\1/g" -e "s/.*NUMA node\s([0-9]+).*/\1/g" 
#

function nvme2busid_full() {
    drv_name=$1
    bdf=$(cat /sys/class/nvme/${drv_name%n*}/address)
    echo ${bdf}
}

function nvme2busid() {
    drv_name=$1
    bdf=$(nvme2busid_full ${drv_name})
    bdf=${bdf##*0000:}
    echo ${bdf}
}

function nvme2busid_spdk() {
    drv_name=$1
    bdf=$(nvme2busid ${drv_name})
    echo ${bdf/:/.}
}

function nvme2numa() {
    drv_name=$1
    bdf=$(nvme2busid ${drv_name})
    if [ ! -z "${bdf}" ]
    then
        echo $(lspci -s ${bdf} -v | grep NUMA | sed -r "s/.*NUMA node\s+([0-9]+).*/\1/g")
    else
        echo ""
    fi    
}

function busid2numa() {
    bdf=$1
    if [ ! -z "${bdf}" ]
    then
        echo $(lspci -s ${bdf} -v | grep NUMA | sed -r "s/.*NUMA node\s+([0-9]+).*/\1/g")
    else
        echo ""
    fi 
}

function busid2desc() {
    bdf=$1
    echo $(lspci -s ${bdf} | cut -d: -f3-)
}

function busid2lnksta() {
    bdf=$1
    echo $(lspci -s ${bdf} -vv | grep LnkSta: | sed -r "s/.*\s+([0-9]+GT).*,.*(x[0-9]+).*/\1+\2/g")
}

function busid2max_pl_rrq() {
    bdf=$1
    echo $(lspci -s ${bdf} -vv | grep DevCtl: -A2 | grep MaxPayload | sed -r "s/\s+MaxPayload\s+([0-9]+)\s+.*MaxReadReq\s+([0-9]+)\s+.*/\1+\2/g")
}

if [ ! -z "`nvme list | grep nvme`" ]
then
    # echo "drive,bdf,numa_node,lnksta,max_pl+rrq,temp,desc"
    print_fmt="%9s%9s%6s%9s%12s%6s  %-s\n"
    printf "${print_fmt}" drive bdf numa lnksta max_pl+rrq temp desc
    for nvme_dev in  `nvme list | sort -V | grep /dev/nvme | cut -d" " -f1`
    do 
        drv=${nvme_dev##*/}
        bdf=$(nvme2busid ${drv})
        if [ ! -z "${bdf}" ]
        then 
            temp=$(nvme smart-log /dev/${drv} | grep temperature | cut -d: -f2)
            numa_node=$(nvme2numa ${drv})
            lnksta=$(busid2lnksta ${bdf})
            max_pl_rq=$(busid2max_pl_rrq ${bdf})
            desc=$(busid2desc ${bdf})
            # echo ${drv}, ${bdf}, ${numa_node}, ${lnksta}, ${max_pl_rq}, ${temp}, ${desc}
            printf "${print_fmt}" ${drv} ${bdf} ${numa_node} ${lnksta} ${max_pl_rq} "${temp}" "${desc}"
        else
            echo "${drv},info not availble"
        fi
    done
else
    header="bdf,numa_node,lnksta,max_pl+rrq,desc"
    # header=(bdf numa lnksta max_pl+rrq desc)
    print_fmt="%9s%6s%9s%12s  %-s\n"
    printf "${print_fmt}" bdf numa lnksta max_pl+rrq desc
    for pcie_dev in  `lspci | grep "Non-Volatile memory controller" | cut -d" " -f1`
    do
        drv=""
        bdf=${pcie_dev}
        numa_node=$(busid2numa ${pcie_dev})
        max_pl_rq=$(busid2max_pl_rrq ${bdf})
        desc=$(lspci -s ${bdf} | cut -d" " -f2-)
        if [ ! -z "${bdf}" ]
        then
            # echo ${bdf},${numa_node},${lnksta},${max_pl_rq},${desc}
            printf "${print_fmt}" ${bdf} ${numa_node} ${lnksta} ${max_pl_rq} "${desc}"
        fi
    done
fi