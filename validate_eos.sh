#!/bin/sh

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eosiovalidate()
{
    eosiocheck || return 1
    if prompt_input_yN "validate snapshot"; then
        printf "absolute path to the csv file: "
        read snapshot
        eosiovalidate_snapshot ${snapshot} || return 1
    fi
    if prompt_input_yN "validate contracts"; then
        printf "absolute path to the built contracts directory: "
        read contracts
        eosiovalidate_contracts ${contracts} || return 1
    fi
}

eosiovalidate_snapshot()
{
    if [ $# -lt 1 ]; then
        printf "usage: eosiovalidate /path/to/snapshot.csv\n"
        printf "pattern: csv, e.g. https://raw.githubusercontent.com/eosauthority/genesis/master/snapshot-files/final/2/snapshot.csv\n"
        return 1
    fi

    SNAPSHOT=$1 ; shift

    if [ ! -f ${SNAPSHOT} ]; then
        printf "${SNAPSHOT} is not a file\n"
        return 1
    fi

    cat ${SNAPSHOT} | tr ' ' '\n' | while read ln; do
        account=$(echo ${ln} | cut -d'"' -f4)
        pubkey=$(echo ${ln} | cut -d'"' -f6)
        balance=$(echo ${ln} | cut -d'"' -f8 | sed 's/\.//')

        printf "account=${account};pubkey=${pubkey};balance=${balance}\n"

        chain_account=$(${cleos} get accounts ${pubkey} | grep "${account}" | sed 's/ \|"\|,//g')
        if [ "${chain_account}" != "${account}" ]; then
            printf "error: cleos get accounts ${pubkey}\n"
            return 1
        fi

        chain_liquid=$(${cleos} get currency balance eosio.token ${account} | cut -d' ' -f1 | sed 's/\.//')
        chain_cpustake=$(${cleos} get account -j ${account} | grep '^  "cpu_weight": ' | cut -d' ' -f4 | sed 's/,\|"//g')
        chain_netstake=$(${cleos} get account -j ${account} | grep '^  "net_weight": ' | cut -d' ' -f4 | sed 's/,\|"//g')

        chain_balance=$((${chain_liquid}+${chain_cpustake}+${chain_netstake}))
        if [ "${balance}" != "${chain_balance}" ]; then
            printf "error: ${chain_liquid} + ${chain_cpustake} + ${chain_netstake} == ${chain_balance} != ${balance}\n"
            return 1
        fi
    done
}

eosiovalidate_contract()
{
    CONTRACT=$1  ; shift
    WASM_PATH=$1 ; shift
    if [ "$(${cleos} get code ${CONTRACT} | cut -d' ' -f3)" != "$(sha256sum ${WASM_PATH} | cut -d' ' -f1)" ]; then
        printf "error: ${CONTRACT} sha256sum mismatch\n"
        return 1
    fi
}

eosiovalidate_contracts()
{
    if [ $# -lt 1 ]; then
        printf "usage: eosiovalidate /path/to/built/contracts_dir\n"
        return 1
    fi

    CONTRACTS_DIR=$1 ; shift
    if [ ! -d ${CONTRACTS_DIR} ]; then
        printf "error: ${CONTRACTS_DIR} file not found\n"
        return 1
    fi

    eosiovalidate_contract "eosio" ${CONTRACTS_DIR}/eosio.bios/eosio.bios.wasm
    eosiovalidate_contract "eosio.msig" ${CONTRACTS_DIR}/eosio.msig/eosio.msig.wasm
    eosiovalidate_contract "eosio.system" ${CONTRACTS_DIR}/eosio.system/eosio.system.wasm
    eosiovalidate_contract "eosio.token" ${CONTRACTS_DIR}/eosio.token/eosio.token.wasm
}

