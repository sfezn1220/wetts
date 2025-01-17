#!/usr/bin/env bash
[ -f path.sh ] && . path.sh

export CUDA_VISIBLE_DEVICES="0"

stage=4
stop_stage=4

# 训练参数
train_version="ft7"
pretrain_generator="F:\models_Yuanshen\exp\\${train_version}\-1"  # '-1' means no pretrain
pretrain_discriminator="F:\models_Yuanshen\exp\\${train_version}\-1"
data="./data/yuanshen-0.5+HoS-1.1+aishell3-1.3"  # data.list 存储路径
ori_label_file="G:\Yuanshen\3.jiaba_cut_16K_yuanshen-0.5+HoS-1.1+aishell3-1.3.txt"  # 原始数据
baker_phones="F:\models_Yuanshen\exp\baker_vits_v1_exp\phones.txt"  # baker 音素列表

# 测试参数
test_epochs="last"
test_gpu="0"

# 一般不需要改的参数
config="configs/${train_version}.json"
exp_dir="F:\models_Yuanshen\exp\\${train_version}"
test_checkpoint="${exp_dir}/G_${test_epochs}.pth"
test_output="${exp_dir}/test_${test_epochs}_epochs"

tools="../../tools"
vits="../../wetts/vits"
. ${tools}/parse_options.sh || exit 1;

# stage 0: make lexicon and phones.
if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
  mkdir -p ${data}
  python ${tools}/gen_pinyin_lexicon.py \
    --with-tone \
    --with-r \
    "${data}/lexicon.list" \
    "${data}/phones.list"
fi

# stage 1: load ori data and make train.txt val.txt and test.txt
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
  # test 10 pieces, valid 100 pieces
  python local/prepare_data.py \
    "${data}/lexicon.list" \
    "${ori_label_file}" \
    "${data}/all.txt" \
    "${data}/test.txt" \
    "${data}/val.txt" \
    "${data}/train.txt"
fi

# stage 2: make phones.txt
if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ]; then
  # phone with 0 is kept for <blank>
  if [ -e ${baker_phones} ]; then {
    cp ${baker_phones} \
      "${data}/phones.txt"
    echo "Use baker phones_dict."
  } else {
    cat "${data}/all.txt" | awk -F '|' '{print $3}' | \
      awk '{ for (i=1;i<=NF;i++) print $i}' | \
      sort | uniq | awk '{print $0, NR}' \
      > "${data}/phones.txt"
    echo "Use self phones_dict."
  } fi
  # 后续不再自动生成 spk-map，改为手动修改；
  # cat "${data}/all.txt" | awk -F '|' '{print $2}' | \
  #   sort | uniq | awk '{print $0, NR-1}' > "${data}/speaker.txt"
fi

# stage 3: train
if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
  echo "starting training... ${vits}/train.py"
  export MASTER_ADDR=localhost
  export MASTER_PORT=10086

  mkdir -p "${exp_dir}/labels_bak"
  cp -r ${data} "${exp_dir}/labels_bak"

  python ${vits}/train.py \
    -c ${config} \
    -m ${exp_dir} \
    --train_data              "${data}/train.txt" \
    --val_data                "${data}/val.txt" \
    --phone_table             "${data}/phones.txt" \
    --speaker_table           "${data}/speaker.txt" \
    --pretrain_generator      "${pretrain_generator}" \
    --pretrain_discriminator  "${pretrain_discriminator}"
fi

# stage 4: test
if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ]; then
  python ${vits}/inference.py  \
    --gpu            ${test_gpu} \
    --checkpoint     ${test_checkpoint} \
    --cfg            ${config} \
    --outdir         ${test_output} \
    --phone_table    "${data}/phones.txt" \
    --test_file      "${data}/test.txt" \
    --speaker_table  "${data}/speaker.txt"
fi