#!/bin/bash

# current path : when you execute this script
cwd=$(pwd)
shell_path=$(cd `dirname $0`; pwd)

. ${shell_path}/config.ini
. ${shell_path}/log.lib

RUN_MODE=$1
INPUT_PATH=$2
OUTPUT_PATH=""

## declare the commond parameters
DEFAULT_AIPP_CONFIG_PATH=${shell_path}/default_aipp.cfg

CONVERT_PARAM=""
DDK_VERSION_VALUE=""

if [[ $# < 2 ]];then
    log_error "Not enough parameters"
    log_warn "Please execute this script like: ./convert.sh \$mode \$file_path [\${output_path}]"
    exit -1
fi

if [[ $# > 2 ]];then
    OUTPUT_PATH=$3
fi

## generate the default aipp cfg file for verify mode
function generate_default_aipp
{
    if [[ -f ${DEFAULT_AIPP_CONFIG_PATH} ]];then
        rm -rf ${DEFAULT_AIPP_CONFIG_PATH}
    fi

    ##  generate the default aipp cfg file
    touch ${DEFAULT_AIPP_CONFIG_PATH}
    echo "input_format : YUV420SP_U8" >> ${DEFAULT_AIPP_CONFIG_PATH} 
    echo "src_image_size_w : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "src_image_size_h : 240" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "csc_switch : true" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "rbuv_swap_switch : false" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r0c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r0c1 : 454" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r0c2 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r1c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r1c1 : -88" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r1c2 : -183" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r2c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r2c1 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "matrix_r2c2 : 359" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "input_bias_0 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "input_bias_1 : 128" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "input_bias_2 : 128" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "min_chn_0 : 104" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "min_chn_1 : 117" >> ${DEFAULT_AIPP_CONFIG_PATH}
    echo "min_chn_2 : 123" >> ${DEFAULT_AIPP_CONFIG_PATH}
}

function generate_c30_aipp_cfg
{
    src_aipp_file=$1
    c30_aipp_file=$2

    if [[ ! -f ${src_aipp_file} ]];then
        log_error "The file ${src_aipp_file} is not exit. Generate for C30 failed!"
        return -1
    fi

    if [[ "X${c30_aipp_file}" == "X" ]];then
        log_error "The C30 aipp file path is not correct! Generate for C30 failed!"
        return -1
    fi

    cp ${src_aipp_file} ${c30_aipp_file}
    if [[ $? -ne 0 ]];then
        log_error "Copy file error. Generate the C30 aipp file failed!"
    fi

    ## "src_image_size_h" exists in the aipp cfg, crop shuold be true,otherwise no need this line
    grep "src_image_size_h" ${c30_aipp_file}
    if [[ $? -eq 0 ]];then
        sed -i '1 i\crop:true' ${c30_aipp_file}
    fi

    sed -i '1 i\aipp_mode:static' ${c30_aipp_file}
    sed -i '1 i\aipp_op{' ${c30_aipp_file}

    sed -i '$a\}' ${c30_aipp_file}
}

# prepare the parameters
function prepare_convert_param
{
    path=$1
    model_name=$2
    type=$3

    CONVERT_PARAM=""

    if [[ "X${type}" == "Xcaffe" ]];then
        CONVERT_PARAM="${CONVERT_PARAM} --framework=0 --model=${path}/${model_name}.prototxt --weight=${path}/${model_name}.caffemodel"
    else
        CONVERT_PARAM="${CONVERT_PARAM} --framework=3 --model=${path}/${model_name}.pb"
    fi

    version_path=$(echo ${DDK_VERSION_VALUE}| sed s/\\./_/g)
    if [[ "X${OUTPUT_PATH}" == "X" ]];then
        output_path=${path}/${version_path}
    else
        output_path=${OUTPUT_PATH}/${version_path}
    fi

    CONVERT_PARAM="${CONVERT_PARAM} --output=${output_path}/${model_name}"

    CONVERT_PARAM="${CONVERT_PARAM} --ddk_version=${DDK_VERSION_VALUE}"

    ## prepare the input shape data
    if [[ "X${RUN_MODE}" == "X0" ]];then
        # in mode 0, you need to input your input shape just the same as in page.
        echo "    Please input the Input Shape."
        echo "    The format is name|N|C|H|W for caffe model and name|N|H|W|C for tensorflow."
        echo -n "    Input shape:"
        read shape
        CONVERT_PARAM="${CONVERT_PARAM} --input_shape=${shape}"
		if [[ ${version_path} =~ ^1_1_T.* ]];then
                CONVERT_PARAM="${CONVERT_PARAM} --aipp_conf=${DEFAULT_AIPP_CONFIG_PATH}"
        else
            # From C30B850, the omg using insert_op_conf instead of aipp_conf command
            b_num=${version_path#*B}
            if [[ $((b_num)) -lt 850 ]];then
                CONVERT_PARAM="${CONVERT_PARAM} --aipp_conf=${DEFAULT_AIPP_CONFIG_PATH}"
            else
                generate_c30_aipp_cfg "${DEFAULT_AIPP_CONFIG_PATH}" "${shell_path}/c30_default_aipp.cfg"
                if [[ $? -ne 0 ]];then
                    log_error "Prepare the aipp file for ${DDK_VERSION_VALUE} failed!"
                    return -1
                fi
                CONVERT_PARAM="${CONVERT_PARAM} --insert_op_conf=${shell_path}/c30_default_aipp.cfg"
            fi
        fi
    else
        # read the input shape with config files
        if [[ -f ${shell_path}/config/${model_name}.shape ]];then
            shape=`cat ${shell_path}/config/${model_name}.shape`
            CONVERT_PARAM="${CONVERT_PARAM} --input_shape=${shape}"
        fi

        if [[ -f ${shell_path}/config/${model_name}_aipp.cfg ]];then
            # C10 version, always use aipp_conf command
            if [[ ${version_path} =~ ^1_1_T.* ]];then
                CONVERT_PARAM="${CONVERT_PARAM} --aipp_conf=${shell_path}/config/${model_name}_aipp.cfg"
            else
                # From C30B850, the omg using insert_op_conf instead of aipp_conf command
                b_num=${version_path#*B}
                if [[ $((b_num)) -lt 850 ]];then
                    CONVERT_PARAM="${CONVERT_PARAM} --aipp_conf=${shell_path}/config/${model_name}_aipp.cfg"
                else
                    generate_c30_aipp_cfg "${shell_path}/config/${model_name}_aipp.cfg" "${shell_path}/config/c30_${model_name}_aipp.cfg"
                    if [[ $? -ne 0 ]];then
                        log_error "Prepare the aipp file for ${DDK_VERSION_VALUE} failed!"
                        return -1
                    fi
                    CONVERT_PARAM="${CONVERT_PARAM} --insert_op_conf=${shell_path}/config/c30_${model_name}_aipp.cfg"
                fi
            fi
        fi

        if [[ -f ${shell_path}/config/${model_name}.opmap ]];then
            CONVERT_PARAM="${CONVERT_PARAM} --op_name_map=${shell_path}/config/${model_name}.opmap"
        fi
    fi
}

function do_convert
{
    path=$1
    model_name=$2
    type=$3

    prepare_convert_param $@
    log_info "Convert with param: $CONVERT_PARAM"

    ${DDK_HOME}/uihost/bin/omg ${CONVERT_PARAM} > ${path}/${model_name}_convert.log
    if [[ $? -ne 0 ]];then
        log_error "Convert the mode ${model_name} failed! Please check the log for more detail"
        return -1
    fi
}

# step 1: convert the input path to absolute path
function convert_input_path
{
    if [[ !(${INPUT_PATH} =~ ^/.*) ]];then
        if [[ ${INPUT_PATH} =~ ^~/.* ]];then
            INPUT_PATH=`echo ${INPUT_PATH}`
        else
            INPUT_PATH=${cwd}/${INPUT_PATH}
        fi
    fi
    INPUT_PATH=$(cd ${INPUT_PATH}; pwd)   ## delete all the ./ ../ path
}

function convert_out_path
{
    if [[ !(${OUTPUT_PATH} =~ ^/.*) ]];then
        if [[ ${OUTPUT_PATH} =~ ^~/.* ]];then
            OUTPUT_PATH=`echo ${OUTPUT_PATH}`
        else
            OUTPUT_PATH=${cwd}/${OUTPUT_PATH}
        fi
    fi

    # create the OUTPUT PATH
    if [[ ! -d ${OUTPUT_PATH} ]];then
        mkdir -p ${OUTPUT_PATH}
        if [[ $? -ne 0 ]];then
            log_error "Create the output flode failed, Please check your input"
            return -1
        fi
    fi

    if [[ ! -w ${OUTPUT_PATH} ]];then
        log_error "Current user have no permission to write to the output floader"
        return -1
    fi
    OUTPUT_PATH=$(cd ${OUTPUT_PATH}; pwd)   ## delete all the ./ ../ path
}

function prepare_org_file
{
    cd ${INPUT_PATH}

    ## list all the prototxt files
    prototxt_file_list=`find ./ -name "*.prototxt"`
    for prototxt_file in ${prototxt_file_list}
    do
        proto_full_path=${INPUT_PATH}/${prototxt_file}
        dir_path=`dirname ${proto_full_path}`
        model_name=`basename ${proto_full_path} ".prototxt"`
        if [[ ! -f ${dir_path}/${model_name}.caffemodel ]];then
            log_error "There is no weight file for ${model_name}."
            continue
        fi

        log_info "Start to convert the mode ${model_name}"
        dir_path=$(cd ${dir_path}; pwd)
        do_convert "${dir_path}" "${model_name}" "caffe"
        if [[ $? -ne 0 ]];then
            log_error "Convert the mode ${model_name} failed!"
        else
            log_info "Convert the mode ${model_name} success!"
        fi
    done

    ## list all the pb files
    pb_file_list=`find ./ -name "*.pb"`
    for pb_file in ${pb_file_list}
    do
        pb_full_path=${INPUT_PATH}/${pb_file}
        dir_path=`dirname ${pb_full_path}`
        model_name=`basename ${pb_full_path} ".pb"`

        log_info "Start to convert the mode ${model_name}"
        dir_path=$(cd ${dir_path}; pwd)
        do_convert "${dir_path}" "${model_name}" "tensorflow"
        if [[ $? -ne 0 ]];then
            log_error "Convert the mode ${model_name} failed!"
        else
            log_info "Convert the mode ${model_name} success!"
        fi
    done
}

## get the versoin number from the ddk info
function get_ddk_version
{
    if [[ -f ${DDK_HOME}/ddk_info ]];then
        version=`cat ${DDK_HOME}/ddk_info | grep "VERSION"`
        DDK_VERSION_VALUE=`echo ${version} | awk -F ':' '{print $2}' | awk -F '"' '{print $2}'`
    else
        log_error "ddk info file is not exist, please check the enviroment."
        return -1
    fi
}

function prepare_env
{
    export SLOG_PRINT_TO_STDOUT=1 
    export PATH=${PATH}:${DDK_HOME}/uihost/toolchains/ccec-linux/bin/ 
    export LD_LIBRARY_PATH=${DDK_HOME}/uihost/lib/ 
    export TVM_AICPU_LIBRARY_PATH=${DDK_HOME}/uihost/lib/:${DDK_HOME}/uihost/toolchains/ccec-linux/aicpu_lib
    export TVM_AICPU_INCLUDE_PATH=${DDK_HOME}/include/inc/tensor_engine
    export PYTHONPATH=${DDK_HOME}/site-packages
    export TVM_AICPU_OS_SYSROOT=/usr/aarch64-linux-gnu 
}

function main
{
    convert_input_path
    if [[ $? -ne 0 ]];then
        log_error "Input path is invalide"
        exit -1
    fi

    if [[ "X${OUTPUT_PATH}" != "X" ]];then
        convert_out_path
        if [[ $? -ne 0 ]];then
            log_error "The output path is invalide."
            exit -1
        fi
    fi

    prepare_env

    get_ddk_version
    if [[ $?  -ne 0 ]];then
        log_error "Get ddk verson info failed!"
        exit -1
    fi

    if [[ "X${RUN_MODE}" == "X0" ]];then
        generate_default_aipp
    fi

    prepare_org_file
    if [[ $? -ne 0 ]];then
        log_error "prepare the file failed!"
        exit -1
    fi

}

main
