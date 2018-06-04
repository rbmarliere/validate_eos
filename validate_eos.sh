#!/bin/sh

source $(dirname "$0")/prompt_input_yN/prompt_input_yN.sh

eosiovalidate()
{
    eosiocheck || return 1

    DATE=$(date +'%Y_%m_%d_%H_%M_%S')
    if prompt_input_yN "write to error-${DATE}.log"; then
        out="error-${DATE}.log"
        touch ${out}
        [ -L errorlog ] && unlink errorlog
        ln -s ${out} errorlog
    fi

    CHAIN=$(${cleos} get info | grep chain_id | cut -d'"' -f4)
    printf "chain_id is ${CHAIN}\n\n" >> ${out:-/dev/stdout}

    eosiovalidate_accounts

    eosiovalidate_supply

    if prompt_input_yN "validate contracts"; then
        printf "built contracts path (/home/ubuntu/git/eos/build/contracts): "
        read contracts
        printf '\n'
        eosiovalidate_contracts ${contracts:-/home/ubuntu/git/eos/build/contracts} || return 1
    fi

    if prompt_input_yN "validate snapshot"; then
        printf "csv file path (./snapshot.csv): "
        read snapshot
        printf '\n'
        eosiovalidate_snapshot ${snapshot:-./snapshot.csv} || return 1
    fi
}

eosiovalidate_accounts()
{
    #['eosio', 'eosio.bpay', 'eosio.msig', 'eosio.names','eosio.ram','eosio.ramfee','eosio.saving','eosio.stake','eosio.token', 'eosio.vpay']
}

eosiovalidate_supply()
{
    max=$(${cleos} get currency stats eosio.token eos | grep max_supply | cut -d'"' -f4 | cut -d' ' -f1 | sed 's/\.//')
    if [ "${max}" != "100000000000000" ]; then
        printf "error: max_supply is not 10000000000.0000 EOS (10bi)\n" >> ${out:-/dev/stdout}
    fi
    supply=$(${cleos} get currency stats eosio.token eos | grep '"supply"' | cut -d'"' -f4 | cut -d' ' -f1 | sed 's/\.//')
    if [ "${supply}" != "10000000000000" ]; then
        printf "error: supply is not 1000000000.0000 EOS (1bi)\n" >> ${out:-/dev/stdout}
    fi
}

eosiovalidate_contract()
{
    CONTRACT=$1  ; shift
    WASM_PATH=$1 ; shift

    if [ ! -f ${WASM_PATH} ]; then
        printf "error: contract ${CONTRACT} ${WASM_PATH} file not found\n"
        return 1
    fi

    code=$(${cleos} get code ${CONTRACT} 2>/dev/null | cut -d' ' -f3)
    sum=$(sha256sum ${WASM_PATH} | cut -d' ' -f1)
    if [ "${code}" = "" ]; then
        printf "error: contract ${CONTRACT} code not found\n" >> ${out:-/dev/stdout}
    elif [ "${code}" != "${sum}" ]; then
        printf "error: contract ${CONTRACT} hash mismatch\n" >> ${out:-/dev/stdout}
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

eosiovalidate_snapshot()
{
    if [ $# -lt 1 ]; then
        printf "usage: eosiovalidate /path/to/snapshot.csv\n"
        return 1
    fi

    SNAPSHOT=$1 ; shift

    if [ ! -f ${SNAPSHOT} ]; then
        printf "${SNAPSHOT} is not a file\n"
        return 1
    fi

    cat ${SNAPSHOT} | while read ln; do
        account=$(echo ${ln} | cut -d'"' -f4)
        pubkey=$(echo ${ln} | cut -d'"' -f6)
        balance=$(echo ${ln} | cut -d'"' -f8 | sed 's/\.//')
        if [ "${account}" = "b1" ]; then
            balance=$((${balance}-10000))
        fi

        printf "account=${account};pubkey=${pubkey};balance=${balance}\n"

        chain_account=$(${cleos} get accounts ${pubkey} | grep "${account}" | sed 's/ \|"\|,//g')
        if [ "${chain_account}" != "${account}" ]; then
            printf "error: account ${chain_account} does not have key ${pubkey}\n" >> ${out:-/dev/stdout}
        fi

        chain_liquid=$(${cleos} get currency balance eosio.token ${account} | cut -d' ' -f1 | sed 's/\.//')
        chain_cpustake=$(${cleos} get account -j ${account} | grep '^  "cpu_weight": ' | cut -d' ' -f4 | sed 's/,\|"//g')
        chain_netstake=$(${cleos} get account -j ${account} | grep '^  "net_weight": ' | cut -d' ' -f4 | sed 's/,\|"//g')
        chain_balance=$((${chain_liquid}+${chain_cpustake}+${chain_netstake}))
        if [ "${balance}" != "${chain_balance}" ]; then
            printf "error: account ${account} has invalid balance ${chain_liquid} (liquid) + ${chain_cpustake} (cpu) + ${chain_netstake} (net) == ${chain_balance} != ${balance}\n" >> ${out:-/dev/stdout}
        fi
    done
}

