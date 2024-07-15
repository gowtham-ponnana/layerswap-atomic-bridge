use starknet::ContractAddress;

#[starknet::interface]
pub trait IMessenger<TContractState> {
    fn notify(
        ref self: TContractState,
        commitId: u256,
        hashlock: u256,
        dstChain: felt252,
        dstAsset: felt252,
        dstAddress: felt252,
        srcAsset: felt252,
        sender: ContractAddress,
        srcReceiver: ContractAddress,
        amount: u256,
        timelock: u256,
        tokenContract: ContractAddress,
    );
}

#[starknet::interface]
pub trait IHashedTimelockERC20<TContractState> {
    fn commit(
        ref self: TContractState,
        amount: u256,
        HopChains: Span<felt252>,
        HopAssets: Span<felt252>,
        HopAddress: Span<felt252>,
        dstChain: felt252,
        dstAsset: felt252,
        dstAddress: felt252,
        srcAsset: felt252,
        srcReceiver: ContractAddress,
        timelock: u256,
        messenger: ContractAddress,
        tokenContract: ContractAddress,
    ) -> u256;
    fn lock(
        ref self: TContractState,
        amount: u256,
        hashlock: u256,
        timelock: u256,
        srcReceiver: ContractAddress,
        srcAsset: felt252,
        dstChain: felt252,
        dstAddress: felt252,
        dstAsset: felt252,
        commitId: u256,
        messenger: ContractAddress,
        tokenContract: ContractAddress,
    ) -> u256;
    fn redeem(ref self: TContractState, lockId: u256, secret: felt252) -> bool;
    fn uncommit(ref self: TContractState, commitId: u256) -> bool;
    fn unlock(ref self: TContractState, lockId: u256) -> bool;
    fn lockCommit(ref self: TContractState, commitId: u256, hashlock: u256) -> u256;
    fn getCommitDetails(
        self: @TContractState, commitId: u256
    ) -> (
        (ContractAddress, ContractAddress, ContractAddress, ContractAddress),
        (u256, felt252, u256),
        (bool, bool),
        felt252
    );
    //fn getHTLContracts(self: @TContractState, sender: ContractAddress) -> Span<u256>;
    fn getLockDetails(
        self: @TContractState, lockId: u256
    ) -> (
        (ContractAddress, ContractAddress, ContractAddress),
        (u256, u256, u256),
        (bool, bool),
        felt252
    );
    fn getCommits(self: @TContractState, sender: ContractAddress) -> Span<u256>;
}

/// @title Pre Hashed Timelock Contracts (PHTLCs) on Starknet ERC20 tokens.
///
/// This contract provides a way to lock and keep PHTLCs for ERC20 tokens.
///
/// Protocol:
///
///  1) lock(srcReceiver, hashlock, timelock, tokenContract, amount) - a
///      sender calls this to lock a new HTLC on a given token (tokenContract)
///       for a given amount. A uint256 lockId is returned
///  2) redeem(lockId, secret) - once the srcReceiver knows the secret of
///      the hashlock hash they can claim the tokens with this function
///  3) unlock(lockId) - after timelock has expired and if the srcReceiver did not
///      redeem the tokens the sender / creator of the HTLC can get their tokens
///      back with this function.
#[starknet::contract]
mod HashedTimelockERC20 {
    use core::clone::Clone;
    use core::array::ArrayTrait;
    use core::num::traits::Zero;
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::interface::IERC20DispatcherTrait;
    use core::traits::Into;
    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    //TODO: Check if this should be IERC20SafeDispatcher 
    use openzeppelin::token::erc20::interface::IERC20Dispatcher;
    use alexandria_math::sha256::sha256;
    use alexandria_bytes::Bytes;
    use alexandria_bytes::BytesTrait;
    use super::IMessenger;
    use super::IMessengerDispatcherTrait;
    use super::IMessengerDispatcher;

    #[storage]
    struct Storage {
        id: u256,
        locks: LegacyMap::<u256, HTLC>,
        commits: LegacyMap::<u256, PHTLC>,
    // contractIds: vec_struct,
    }

    // #[derive(Drop, Serde, starknet::Store)]
    // struct vec_struct {
    //     ids: Span<u256>,
    // }
    //TDOO: check if this should be public?
    #[derive(Drop, Serde, starknet::Store)]
    struct HTLC {
        dstAddress: felt252,
        dstChain: felt252,
        dstAsset: felt252,
        srcAsset: felt252,
        sender: ContractAddress,
        srcReceiver: ContractAddress,
        hashlock: u256,
        secret: felt252,
        amount: u256,
        timelock: u256,
        tokenContract: ContractAddress,
        redeemed: bool,
        unlocked: bool,
    }
    #[derive(Drop, Serde, starknet::Store)]
    struct PHTLC {
        dstAddress: felt252,
        dstChain: felt252,
        dstAsset: felt252,
        srcAsset: felt252,
        sender: ContractAddress,
        srcReceiver: ContractAddress,
        amount: u256,
        timelock: u256,
        messenger: ContractAddress,
        tokenContract: ContractAddress,
        locked: bool,
        uncommitted: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        TokenCommitted: TokenCommitted,
        TokenLocked: TokenLocked,
        TokenRedeemed: TokenRedeemed,
        TokenUnlocked: TokenUnlocked,
        TokenUncommitted: TokenUncommitted,
    }
    #[derive(Drop, starknet::Event)]
    struct TokenCommitted {
        commitId: u256,
        HopChains: Span<felt252>,
        HopAssets: Span<felt252>,
        HopAddress: Span<felt252>,
        dstChain: felt252,
        dstAddress: felt252,
        dstAsset: felt252,
        #[key]
        sender: ContractAddress,
        #[key]
        srcReceiver: ContractAddress,
        srcAsset: felt252,
        amount: u256,
        timelock: u256,
        messenger: ContractAddress,
        tokenContract: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    struct TokenLocked {
        #[key]
        hashlock: u256,
        dstChain: felt252,
        dstAddress: felt252,
        dstAsset: felt252,
        #[key]
        sender: ContractAddress,
        #[key]
        srcReceiver: ContractAddress,
        srcAsset: felt252,
        amount: u256,
        timelock: u256,
        messenger: ContractAddress,
        tokenContract: ContractAddress,
        commitId: u256,
    }
    #[derive(Drop, starknet::Event)]
    struct TokenRedeemed {
        #[key]
        lockId: u256,
        redeemAddress: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    struct TokenUnlocked {
        #[key]
        lockId: u256
    }
    #[derive(Drop, starknet::Event)]
    struct TokenUncommitted {
        #[key]
        commitId: u256
    }
    #[constructor]
    fn constructor(ref self: ContractState) {
        // let mut arr: Array<u256> = ArrayTrait::new();
        // let span_arr = arr.span();
        // self.contractIds.write(span_arr);
        self.id.write(0);
    }
    #[abi(embed_v0)]
    impl HashedTimelockERC20 of super::IHashedTimelockERC20<ContractState> {
        /// @dev Sender / Payer sets up a new pre-hash time lock contract depositing the
        /// funds and providing the reciever/srcReceiver and terms.
        /// @param srcReceiver reciever/srcReceiver of the funds.
        /// @param timelock UNIX epoch seconds time that the lock expires at.
        ///                  Refunds can be made after this time.
        /// @return Id of the new PHTLC. This is needed for subsequent calls.
        fn commit(
            ref self: ContractState,
            amount: u256,
            HopChains: Span<felt252>,
            HopAssets: Span<felt252>,
            HopAddress: Span<felt252>,
            dstChain: felt252,
            dstAsset: felt252,
            dstAddress: felt252,
            srcAsset: felt252,
            srcReceiver: ContractAddress,
            timelock: u256,
            messenger: ContractAddress,
            tokenContract: ContractAddress,
        ) -> u256 {
            assert!(timelock > get_block_timestamp().into(), "Not Future TimeLock");
            assert!(amount != 0, "Funds Can Not Be Zero");

            let commitId = self.id.read() + 1;
            self.id.write(commitId);

            let token: IERC20Dispatcher = IERC20Dispatcher { contract_address: tokenContract };
            assert!(token.balance_of(get_caller_address()) >= amount, "Insufficient Balance");
            assert!(
                token.allowance(get_caller_address(), get_contract_address()) >= amount,
                "Not Enough Allowence"
            );

            token.transfer_from(get_caller_address(), get_contract_address(), amount);

            self
                .commits
                .write(
                    commitId,
                    PHTLC {
                        dstAddress: dstAddress,
                        dstChain: dstChain,
                        dstAsset: dstAsset,
                        srcAsset: srcAsset,
                        sender: get_caller_address(),
                        srcReceiver: srcReceiver,
                        amount: amount,
                        timelock: timelock,
                        messenger: messenger,
                        tokenContract: tokenContract,
                        locked: false,
                        uncommitted: false,
                    }
                );
            self
                .emit(
                    TokenCommitted {
                        commitId: commitId,
                        HopChains: HopChains,
                        HopAssets: HopAssets,
                        HopAddress: HopAddress,
                        dstChain: dstChain,
                        dstAddress: dstAddress,
                        dstAsset: dstAsset,
                        sender: get_caller_address(),
                        srcReceiver: srcReceiver,
                        srcAsset: srcAsset,
                        amount: amount,
                        timelock: timelock,
                        messenger: messenger,
                        tokenContract: tokenContract,
                    }
                );
            commitId
        }

        /// @dev Sender / Payer sets up a new hash time lock contract depositing the
        /// funds and providing the reciever and terms.
        /// @param srcReceiver srcReceiver of the funds.
        /// @param hashlock A sha-256 hash hashlock.
        /// @param timelock UNIX epoch seconds time that the lock expires at.
        ///                  Refunds can be made after this time.
        /// @return Id of the new HTLC. This is needed for subsequent calls.
        fn lock(
            ref self: ContractState,
            amount: u256,
            hashlock: u256,
            timelock: u256,
            srcReceiver: ContractAddress,
            srcAsset: felt252,
            dstChain: felt252,
            dstAddress: felt252,
            dstAsset: felt252,
            commitId: u256,
            messenger: ContractAddress,
            tokenContract: ContractAddress,
        ) -> u256 {
            assert!(timelock > get_block_timestamp().into(), "Not Future TimeLock");
            assert!(amount != 0, "Funds Can Not Be Zero");

            let lockId = hashlock;
            assert!(!self.hasLockId(lockId), "HTLC Already Exists");

            let token: IERC20Dispatcher = IERC20Dispatcher { contract_address: tokenContract };
            assert!(token.balance_of(get_caller_address()) >= amount, "Insufficient Balance");
            assert!(
                token.allowance(get_caller_address(), get_contract_address()) >= amount,
                "Not Enough Allowence"
            );

            token.transfer_from(get_caller_address(), get_contract_address(), amount);
            self
                .locks
                .write(
                    lockId,
                    HTLC {
                        dstAddress: dstAddress,
                        dstChain: dstChain,
                        dstAsset: dstAsset,
                        srcAsset: srcAsset,
                        sender: get_caller_address(),
                        srcReceiver: srcReceiver,
                        hashlock: hashlock,
                        secret: 0,
                        amount: amount,
                        timelock: timelock,
                        tokenContract: tokenContract,
                        redeemed: false,
                        unlocked: false
                    }
                );
            self
                .emit(
                    TokenLocked {
                        hashlock: hashlock,
                        dstChain: dstChain,
                        dstAddress: dstAddress,
                        dstAsset: dstAsset,
                        sender: get_caller_address(),
                        srcReceiver: srcReceiver,
                        srcAsset: srcAsset,
                        amount: amount,
                        timelock: timelock,
                        messenger: messenger,
                        tokenContract: tokenContract,
                        commitId: commitId,
                    }
                );
            if !messenger.is_zero() {
                let messenger: IMessengerDispatcher = IMessengerDispatcher {
                    contract_address: messenger
                };
                messenger
                    .notify(
                        commitId,
                        hashlock,
                        dstChain,
                        dstAsset,
                        dstAddress,
                        srcAsset,
                        get_caller_address(),
                        srcReceiver,
                        amount,
                        timelock,
                        tokenContract,
                    );
            }
            lockId
        }

        /// @dev Called by the srcReceiver once they know the secret of the hashlock.
        /// This will transfer the locked funds to their address.
        ///
        /// @param lockId of the HTLC.
        /// @param secret sha256(secret) should equal the contract hashlock.
        /// @return bool true on success
        fn redeem(ref self: ContractState, lockId: u256, secret: felt252) -> bool {
            assert!(self.hasLockId(lockId), "Lock Id Does Not Exist");
            let htlc: HTLC = self.locks.read(lockId);

            let mut bytes: Bytes = BytesTrait::new(0, array![]);
            bytes.append_felt252(secret);
            let pre = bytes.sha256();
            let mut bytes: Bytes = BytesTrait::new(0, array![]);
            bytes.append_u256(pre);
            let hash_pre = bytes.sha256();
            assert!(htlc.hashlock == hash_pre, "Does Not Match the Hashlock");
            assert!(!htlc.redeemed, "Funds Are Alredy Redeemed");
            assert!(!htlc.unlocked, "Funds Are Alredy Unlocked");
            self
                .locks
                .write(
                    lockId,
                    HTLC {
                        dstAddress: htlc.dstAddress,
                        dstChain: htlc.dstChain,
                        dstAsset: htlc.dstAsset,
                        srcAsset: htlc.srcAsset,
                        sender: htlc.sender,
                        srcReceiver: htlc.srcReceiver,
                        hashlock: htlc.hashlock,
                        secret: secret,
                        amount: htlc.amount,
                        timelock: htlc.timelock,
                        tokenContract: htlc.tokenContract,
                        redeemed: true,
                        unlocked: htlc.unlocked
                    }
                );
            IERC20Dispatcher { contract_address: htlc.tokenContract }
                .transfer(htlc.srcReceiver, htlc.amount);
            self.emit(TokenRedeemed { lockId: lockId, redeemAddress: get_caller_address() });
            true
        }

        /// @dev Called by the sender if there was no redeem OR lockCommit AND the time lock has
        /// expired. This will unlock the contract amount.
        ///
        /// @param commitId of the PHTLC to unlock from.
        /// @return bool true on success
        fn uncommit(ref self: ContractState, commitId: u256) -> bool {
            assert!(commitId <= self.id.read(), "Commitment Id Does Not Exist");
            let phtlc: PHTLC = self.commits.read(commitId);

            assert!(!phtlc.uncommitted, "Funds Are Already Uncommitted");
            assert!(!phtlc.locked, "Funds Are Already Locked");
            assert!(phtlc.timelock <= get_block_timestamp().into(), "Not Passed Time Lock");

            self
                .commits
                .write(
                    commitId,
                    PHTLC {
                        dstAddress: phtlc.dstAddress,
                        dstChain: phtlc.dstChain,
                        dstAsset: phtlc.dstAsset,
                        srcAsset: phtlc.srcAsset,
                        sender: phtlc.sender,
                        srcReceiver: phtlc.srcReceiver,
                        amount: phtlc.amount,
                        timelock: phtlc.timelock,
                        messenger: phtlc.messenger,
                        tokenContract: phtlc.tokenContract,
                        locked: phtlc.locked,
                        uncommitted: true,
                    }
                );
            IERC20Dispatcher { contract_address: phtlc.tokenContract }
                .transfer(phtlc.sender, phtlc.amount);
            self.emit(TokenUncommitted { commitId: commitId });
            true
        }

        /// @dev Called by the sender if there was no redeem AND the time lock has
        /// expired. This will unlock the contract amount.
        ///
        /// @param lockId of the HTLC to unlock from.
        /// @return bool true on success
        fn unlock(ref self: ContractState, lockId: u256) -> bool {
            assert!(self.hasLockId(lockId), "Lock Id Does Not Exist");
            let htlc: HTLC = self.locks.read(lockId);

            assert!(!htlc.redeemed, "Funds Are Already Redeemed");
            assert!(!htlc.unlocked, "Funds Are Already Unlocked");
            assert!(htlc.timelock <= get_block_timestamp().into(), "Not Passed Time Lock");

            self
                .locks
                .write(
                    lockId,
                    HTLC {
                        dstAddress: htlc.dstAddress,
                        dstChain: htlc.dstChain,
                        dstAsset: htlc.dstAsset,
                        srcAsset: htlc.srcAsset,
                        sender: htlc.sender,
                        srcReceiver: htlc.srcReceiver,
                        hashlock: htlc.hashlock,
                        secret: htlc.secret,
                        amount: htlc.amount,
                        timelock: htlc.timelock,
                        tokenContract: htlc.tokenContract,
                        redeemed: htlc.redeemed,
                        unlocked: true
                    }
                );
            IERC20Dispatcher { contract_address: htlc.tokenContract }
                .transfer(htlc.sender, htlc.amount);
            self.emit(TokenUnlocked { lockId: lockId });
            true
        }

        /// @dev Called by the sender to lockCommit the PHTLC to HTLC
        /// expired. This will unlock the contract amount.
        ///
        /// @param commitId of the PHTLC to lockCommit.
        /// @param hashlock of the HTLC to be locked.
        /// @return id of the locked HTLC
        fn lockCommit(ref self: ContractState, commitId: u256, hashlock: u256) -> u256 {
            assert!(commitId <= self.id.read(), "Commitment Id Does Not Exist");
            let lockId = hashlock;
            let phtlc: PHTLC = self.commits.read(commitId);

            assert!(!phtlc.uncommitted, "Can't Lock Uncommitted Funds");
            assert!(!phtlc.locked, "Funds Are Already Locked");
            assert!(!self.hasLockId(lockId), "Lock Id Already Exist");
            assert!(
                get_caller_address() == phtlc.sender || get_caller_address() == phtlc.messenger,
                "No Allowance"
            );
            self
                .commits
                .write(
                    commitId,
                    PHTLC {
                        dstAddress: phtlc.dstAddress,
                        dstChain: phtlc.dstChain,
                        dstAsset: phtlc.dstAsset,
                        srcAsset: phtlc.srcAsset,
                        sender: phtlc.sender,
                        srcReceiver: phtlc.srcReceiver,
                        amount: phtlc.amount,
                        timelock: phtlc.timelock,
                        messenger: phtlc.messenger,
                        tokenContract: phtlc.tokenContract,
                        locked: true,
                        uncommitted: phtlc.uncommitted,
                    }
                );
            self
                .locks
                .write(
                    lockId,
                    HTLC {
                        dstAddress: phtlc.dstAddress,
                        dstChain: phtlc.dstChain,
                        dstAsset: phtlc.dstAsset,
                        srcAsset: phtlc.srcAsset,
                        sender: phtlc.sender,
                        srcReceiver: phtlc.srcReceiver,
                        hashlock: hashlock,
                        secret: 0,
                        amount: phtlc.amount,
                        timelock: phtlc.timelock,
                        tokenContract: phtlc.tokenContract,
                        redeemed: false,
                        unlocked: false
                    }
                );
            self
                .emit(
                    TokenLocked {
                        hashlock: hashlock,
                        dstAddress: phtlc.dstAddress,
                        dstChain: phtlc.dstChain,
                        dstAsset: phtlc.dstAsset,
                        sender: phtlc.sender,
                        srcReceiver: phtlc.srcReceiver,
                        srcAsset: phtlc.srcAsset,
                        amount: phtlc.amount,
                        timelock: phtlc.timelock,
                        messenger: phtlc.messenger,
                        tokenContract: phtlc.tokenContract,
                        commitId: commitId,
                    }
                );
            lockId
        }

        /// @dev Get HTLC details.
        /// @param lockId of the HTLC.
        fn getLockDetails(
            self: @ContractState, lockId: u256
        ) -> (
            (ContractAddress, ContractAddress, ContractAddress),
            (u256, u256, u256),
            (bool, bool),
            felt252
        ) {
            if !self.hasLockId(lockId) {
                return (
                    (Zero::zero(), Zero::zero(), Zero::zero()),
                    (0_u256, 0_u256, 0_u256),
                    (false, false),
                    0
                );
            }
            let htlc: HTLC = self.locks.read(lockId);
            (
                (htlc.sender, htlc.srcReceiver, htlc.tokenContract),
                (htlc.amount, htlc.hashlock, htlc.timelock),
                (htlc.redeemed, htlc.unlocked),
                htlc.secret
            )
        }
        // fn getHTLContracts(self: @ContractState, sender: ContractAddress) -> Span<u256> {
        //     let mut arr: Array<u256> = ArrayTrait::new();
        //     let contractIds: Span<u256> = self.contractIds.read().clone();
        //     let len = contractIds.len();
        //     let mut i: usize = 0;
        //     while i < len {
        //         let lockId = *contractIds[i];
        //         let htlc: HTLC = self.locks.read(lockId);
        //         if htlc.sender == sender {
        //             arr.append(lockId);
        //         }
        //         i += 1;
        //     };
        //     arr.span()
        // }
        fn getCommitDetails(
            self: @ContractState, commitId: u256
        ) -> (
            (ContractAddress, ContractAddress, ContractAddress, ContractAddress),
            (u256, felt252, u256),
            (bool, bool),
            felt252
        ) {
            if commitId > self.id.read() {
                return (
                    (Zero::zero(), Zero::zero(), Zero::zero(), Zero::zero()),
                    (0_u256, 0, 0_u256),
                    (false, false),
                    0
                );
            }
            let phtlc: PHTLC = self.commits.read(commitId);
            (
                (phtlc.sender, phtlc.srcReceiver, phtlc.tokenContract, phtlc.messenger),
                (phtlc.amount, phtlc.srcAsset, phtlc.timelock),
                (phtlc.uncommitted, phtlc.locked),
                phtlc.dstAddress
            )
        }
        fn getCommits(self: @ContractState, sender: ContractAddress) -> Span<u256> {
            let mut arr: Array<u256> = ArrayTrait::new();
            let mut i: u256 = 1;
            while i <= self
                .id
                .read() {
                    let phtlc: PHTLC = self.commits.read(i);
                    if phtlc.sender == sender {
                        arr.append(i);
                    }
                    i += 1;
                };
            arr.span()
        }
    }

    #[generate_trait]
    //TODO: Check if this functions be inline?
    impl InternalFunctions of InternalFunctionsTrait {
        /// @dev Check if there is a HTLC with a given htlcId.
        /// @param lockId into HTLC mapping.
        fn hasLockId(self: @ContractState, lockId: u256) -> bool {
            let exists: bool = (!self.locks.read(lockId).sender.is_zero());
            exists
        }
    }
}
