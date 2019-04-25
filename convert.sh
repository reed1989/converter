#!/bin/bash

cwd=$(pwd)
shell_path=$(cd `dirname $0`; pwd)

RUN_MODE=$1
INPUT_PATH=$2
OUTPUT_PATH=""

## declare the commond parameters
MODE_VALUE=0
DEFAULT_AIPP_CONFIG_PATH=${shell_path}/default_aipp.cfg


OP_NAME_MAP_VALUE=""
DDK_VERSION_VALUE=""

function log
{
	log_level=$1
	msg=$2

	time_stamp=$(date "+%Y-%m-%d %H:%M:%S")

	echo "${time_stamp} [${log_level}] ${msg}"
}

function log_info
{
	log "INFO" "$*"
}

function log_warn
{
	log "WARN" "$*"
}

function log_error
{
	log "ERROR" "$*"
}

if [[ $# < 2 ]];then
	log_error "Not enough parameters"
	log_warn "Please execute this script like: ./convert.sh \$mode \$file_path [\${output_path}]"
	exit
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
	echo ""
	echo "input_format : YUV420SP_U8" >> ${DEFAULT_AIPP_CONFIG_PATH} 
	echo "icsc_switch : true" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "irbuv_swap_switch : false" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r0c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r0c1 : 454" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r0c2 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r1c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r1c1 : -88" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r1c2 : -183" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r2c0 : 256" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r2c1 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imatrix_r2c2 : 359" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "iinput_bias_0 : 0" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "iinput_bias_1 : 128" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "iinput_bias_2 : 128" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imin_chn_0 : 104" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imin_chn_1 : 117" >> ${DEFAULT_AIPP_CONFIG_PATH}
	echo "imin_chn_2 : 123" >> ${DEFAULT_AIPP_CONFIG_PATH}
}

function do_convert
{
	path=$1
	model_name=$2
	type=$3

	## prepare the input shape data
	if [[ "X${RUN_MODE}" == "X)" ]];then
		echo -n "	Please input the Input Shape"
		read input_shape
		aipp_cfg_path=${DEFAULT_AIPP_CONFIG_PATH}
	else
		input_shape=`cat ${path}/${model_name}.shape`
		aipp_cfg_path="${path}/${model_name}_aipp.cfg"
	fi

	if [[ "X${type}" == "Xcaffe" ]];then
		${DDK_HOME}/uihost/bin/omg --framework=0 --output=${path}/${model_name} --model=${path}/${model_name}.prototxt --weight=${path}/${model_name}.caffemodel --ddk_verion=${DDK_VERSION_VALUE} --input_shape="${input_shape}" --aipp_conf=${aipp_cfg_path} > ${path}/${model_name}_convert.log
	else
		${DDK_HOME}/uihost/bin/omg --framework=3 --output=${path}/${model_name} --model=${path}/${model_name}.pb --ddk_verion=${DDK_VERSION_VALUE} --input_shape="${input_shape}" --aipp_conf=${aipp_cfg_path} > ${path}/${model_name}_convert.log
	fi

	if [[ $? -ne 0 ]];then
		log_error "Convert the mode ${model_name} failed! Please check the log for more detail"
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

function prepare_org_file
{
	cd ${INPUT_PATH}

	## list all the prototxt files
	prototxt_file_list=`find ./ -name "*.prototxt"`
	for prototxt_file in ${prototxt_file_list}
	do
		proto_full_path=${INPUT_PATH}/${prototxt_file}
		dir_path=`dirname ${prototxt_file}`
		model_name=`basename ${proto_full_path} ".prototxt"`
		if [[ ! -f ${dir_path}/${model_name}.caffemodel ]];then
			log_error "There is no weight file for ${model_name}."
			continue
		fi

		# check the inpt shape and aipp config file
		if [[ "X${RUN_MODE}" == "X1" ]];then
			if [[ ! -f ${dir_path}/${model_name}.shape ]];then
				echo -n "    There is no input shape file for ${model_name}."
				echo -n "	 Please input the Input Shape"
		        read input_shape
		        echo ${input_shape} > ${dir_path}/${model_name}.shape
		    fi

		    if [[ ! -f ${dir_path}/$${model_name}_aipp.cfg ]];then
		    	log_error "There is no aipp config file for ${model_name}"
		    	continue
		    fi
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

		# check the inpt shape and aipp config file
		if [[ "X${RUN_MODE}" == "X1" ]];then
			if [[ ! -f ${dir_path}/${model_name}.shape ]];then
				echo -n "    There is no input shape file for ${model_name}."
				echo -n "	 Please input the Input Shape"
		        read input_shape
		        echo ${input_shape} > ${dir_path}/${model_name}.shape
		    fi

		    if [[ ! -f ${dir_path}/${model_name}_aipp.cfg ]];then
		    	log_error "There is no aipp config file for ${model_name}"
		    	continue
		    fi
		fi

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
	export DDK_HOME=/
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
		exit
	fi

	prepare_env

	get_ddk_version
	if [[ $?  -ne 0 ]];then
		log_error "Get ddk verson info failed!"
		exit
	fi

	if [[ "X${RUN_MODE}" == "X0" ]];then
		generate_default_aipp
	fi

	prepare_org_file
	if [[ $? -ne 0 ]];then
		log_error "prepare the file failed!"
		exit
	fi

}

main