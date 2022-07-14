#!/bin/bash
#
# lspci -d1e3b: -v | grep -e NUMA -e Non-Vol | sed -r -e "s/(.*)\s+Non-Vol.*/\1/g" -e "s/.*NUMA node\s([0-9]+).*/\1/g" 
#

function nvme2busid_full() {
    drv_name=$1
    busid=$(cat /sys/class/nvme/${drv_name%n*}/address)
    echo ${busid}
}

function nvme2busid() {
    drv_name=$1
    busid=$(nvme2busid_full ${drv_name})
    busid=${busid##*0000:}
    echo ${busid}
}

function nvme2busid_spdk() {
    drv_name=$1
    busid=$(nvme2busid ${drv_name})
    echo ${busid/:/.}
}

function nvme2numa() {
    drv_name=$1
    busid=$(nvme2busid ${drv_name})
    if [ ! -z "${busid}" ]
    then
        echo $(lspci -s ${busid} -v | grep NUMA | sed -r "s/.*NUMA node\s+([0-9]+).*/\1/g")
    else
        echo ""
    fi    
}

function busid2numa() {
    busid=$1
    if [ ! -z "${busid}" ]
    then
        echo $(lspci -s ${busid} -v | grep NUMA | sed -r "s/.*NUMA node\s+([0-9]+).*/\1/g")
    else
        echo ""
    fi 
}

function busid2desc() {
    busid=$1
    echo $(lspci -s ${busid} | cut -d: -f3-)
}

function busid2lnksta() {
    busid=$1
    echo $(lspci -s ${busid} -vv | grep LnkSta: | sed -r "s/.*\s+([0-9]+GT).*,.*(x[0-9]+).*/\1+\2/g")
}

function busid2max_pl_rrq() {
    busid=$1
    echo $(lspci -s ${busid} -vv | grep DevCtl: -A2 | grep MaxPayload | sed -r "s/\s+MaxPayload\s+([0-9]+)\s+.*MaxReadReq\s+([0-9]+)\s+.*/\1+\2/g")
}

echo "drive,busid,numa_node,lnksta,max_payload+readreq,desc"

if [ ! -z "`nvme list | grep nvme`" ]
then
    for nvme_dev in  `nvme list | sort -V | grep /dev/nvme | cut -d" " -f1`
    do 
        drv=${nvme_dev##*/}
        busid=$(nvme2busid ${drv})
        if [ ! -z ${busid} ]
        then 
            numa_node=$(nvme2numa ${drv})
            lnksta=$(busid2lnksta ${busid})
            max_pl_rq=$(busid2max_pl_rrq ${busid})
            desc=$(busid2desc ${busid})
            echo ${drv},${busid},${numa_node},${lnksta},${max_pl_rq},${desc}
        else
            echo "${drv},info not availble"
        fi
    done
else
    for pcie_dev in  `lspci | grep "Non-Volatile memory controller" | cut -d" " -f1`
    do
        drv=""
        busid=${pcie_dev}
        numa_node=$(busid2numa ${pcie_dev})
        max_pl_rq=$(busid2max_pl_rrq ${busid})
        desc=$(lspci -s ${busid} | cut -d" " -f2-)
        if [ ! -z ${busid} ]
        then
            echo ${drv},${busid},${numa_node},${max_pl_rq},${desc}
        fi
    done
fi