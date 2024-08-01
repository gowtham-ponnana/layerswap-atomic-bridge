import assert from "assert";
import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Keypair } from "@solana/web3.js";
import { NativeHtlc } from '../target/types/sol';

interface PDAParameters {
  htlcKey: anchor.web3.PublicKey;
  htlcBump: number;
  phtlcKey: anchor.web3.PublicKey;
  phtlcBump: number;
  lockIdStruct: anchor.web3.PublicKey;
}

describe("safe_pay", () => {
  // Configure the client to use the local cluster.
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.NativeHtlc as anchor.Program<NativeHtlc>;

  const wallet = provider.wallet as anchor.Wallet;
  const SECRET = "31";
  const COMMITID = SECRET;
  const HASHLOCK = "297c82b1ad2faaed2a91aa5a74a4c61120fe817290b7579cd92d44c3e4d354cd";
  const LOCKID = HASHLOCK.slice(0, 32);
  console.log(`${LOCKID} ID`);
  const AMOUNT = 0.01 * anchor.web3.LAMPORTS_PER_SOL;
  const DSTCHAIN = "ETHEREUM";
  const DSTASSET = "ETH";
  const SRCASSET = "SOL";
  const DSTADDRESS = "0";
  const HOPCHAINS = [DSTCHAIN];
  const HOPASSETS = [DSTASSET];
  const HOPADDRESSES = [DSTADDRESS];

  let alice: anchor.web3.Keypair;
  let bob: anchor.web3.Keypair;

  let pda: PDAParameters;

  const getPdaParams = async (
    lock_id: string,
    commit_id: string,
  ): Promise<PDAParameters> => {
    let seed = Buffer.from(lock_id);
    let pseed = Buffer.from(commit_id);
    let [htlc, htlcBump] = await anchor.web3.PublicKey.findProgramAddressSync(
      [seed],
      program.programId
    );
    console.log(`[${htlc}] derived htlc`);

    let [phtlc, phtlcBump] = await anchor.web3.PublicKey.findProgramAddressSync(
      [pseed],
      program.programId
    );
    console.log(`[${phtlc}] derived phtlc`);

    let [lockIdStruct, _] = await anchor.web3.PublicKey.findProgramAddressSync(
      [Buffer.from("commit_to_lock"), pseed],
      program.programId
    );
    return {
      htlcKey: htlc,
      htlcBump,
      phtlcKey: phtlc,
      phtlcBump,
      lockIdStruct,
    };
  };

  const createUser = async (): Promise<anchor.web3.Keypair> => {
    const user = new anchor.web3.Keypair();
    // Fund user with some SOL
    let txFund = new anchor.web3.Transaction();
    txFund.add(
      anchor.web3.SystemProgram.transfer({
        fromPubkey: provider.wallet.publicKey,
        toPubkey: user.publicKey,
        lamports: 0.05 * anchor.web3.LAMPORTS_PER_SOL,
      })
    );
    const sigTxFund = await provider.sendAndConfirm(txFund);
    console.log(`[${user.publicKey.toBase58()}] Funded new account with 0.005 SOL: ${sigTxFund}`);
    return user;
  };

  function wait(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  before(async () => {
    alice = await createUser();
    bob = await createUser();

    pda = await getPdaParams(LOCKID, COMMITID);
  });
  // it("create prehtlc", async () => {

  //   const TIME = new Date().getTime();
  //   const TIMELOC = (TIME + 2500) / 1000;
  //   const TIMELOCK = new anchor.BN(TIMELOC);
  //   console.log(`[${TIMELOC * 1000}] the Timelock`);

  //   const tx1 = await program.methods
  //     .commit(COMMITID, HOPCHAINS, HOPASSETS, HOPADDRESSES, DSTCHAIN, DSTASSET, DSTADDRESS, SRCASSET, bob.publicKey, TIMELOCK, alice.publicKey, new anchor.BN(AMOUNT), pda.phtlcBump)
  //     .accountsPartial({
  //       phtlc: pda.phtlcKey,
  //       sender: alice.publicKey,
  //     })
  //     .signers([alice])
  //     .rpc();
  //   console.log(`Initialized a new PHTLC. Alice will pay bob 0.01 sol`);

  //   // await wait(3000);
  //   // const CURTIME = new Date().getTime() / 1000;
  //   // console.log(`[${CURTIME * 1000}] CURRENT TIME`);
  //   // const tx2 = await program.methods.uncommit(COMMITID, pda.phtlcBump).
  //   //   accountsPartial({
  //   //     phtlc: pda.phtlcKey,
  //   //     // userSigning: alice.publicKey,
  //   //     userSigning: wallet.publicKey,
  //   //     sender: alice.publicKey,
  //   //   })
  //   //   .signers([wallet.payer])
  //   //   .rpc();
  //   // console.log(`can uncommit`);

  //   const tx3 = await program.methods.lockCommit(COMMITID, LOCKID, HASHLOCK, pda.phtlcBump).
  //     accountsPartial({
  //       phtlc: pda.phtlcKey,
  //       htlc: pda.htlcKey,
  //       // userSigning: alice.publicKey,
  //       userSigning: alice.publicKey,
  //     })
  //     .signers([alice])
  //     .rpc();//.catch(e => console.error(e));
  //   console.log(`can lockCommit`);

  //   const details = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
  //   console.log(`${details} details`);
  //   // const tx4 = await program.methods.redeem(LOCKID, SECRET, pda.htlcBump).
  //   //   accountsPartial({
  //   //     htlc: pda.htlcKey,
  //   //     userSigning: alice.publicKey,
  //   //     srcReceiver: bob.publicKey,
  //   //   })
  //   //   .signers([alice])
  //   //   .rpc();


  //   await wait(2000);
  //   const tx5 = await program.methods.unlock(LOCKID, pda.htlcBump).
  //     accountsPartial({
  //       htlc: pda.htlcKey,
  //       // userSigning: alice.publicKey,
  //       userSigning: wallet.publicKey,
  //       sender: alice.publicKey,
  //     })
  //     .signers([wallet.payer])
  //     .rpc();

  //   // const tx0 = await program.methods
  //   //   .lock(LOCKID, HASHLOCK, TIMELOCK, new anchor.BN(AMOUNT),DSTASSET, DSTCHAIN, DSTADDRESS, DSTASSET,COMMITID, pda.htlcKey, pda.htlcBump)
  //   //   .accountsPartial({
  //   //     htlc: pda.htlcKey,
  //   //     sender: alice.publicKey,
  //   //   })
  //   //   .signers([alice])
  //   //   .rpc();

  //   // const postdetails = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
  // });



  it("Bob can redeem", async () => {

    const amount = new anchor.BN(20000000);
    const TIME = new Date().getTime();
    const TIMELOC = (TIME + 2500) / 1000;
    const TIMELOCK = new anchor.BN(TIMELOC);
    console.log(`[${TIMELOC * 1000}] the Timelock`);
    console.log("lamport balance of htlc at the beginning",
      await anchor.getProvider().connection.getBalance(pda.htlcKey));
    console.log("lamport balance of alice before creation",
      await anchor.getProvider().connection.getBalance(alice.publicKey));
    const tx1 = await program.methods
      .lock(LOCKID, COMMITID, HASHLOCK, TIMELOCK, new anchor.BN(AMOUNT), DSTASSET, DSTCHAIN, DSTADDRESS, SRCASSET, bob.publicKey, pda.htlcKey, pda.htlcBump)
      .accountsPartial({
        htlc: pda.htlcKey,
        lockIdStruct: pda.lockIdStruct,
        sender: alice.publicKey,
      })
      .signers([alice])
      .rpc();
    console.log(`Initialized a new Safe Pay instance. Alice will pay bob 20 tokens`);

    // Assert that 20 tokens were moved from Alice's account to the escrow.
    // const [, aliceBalancePost] = await readAccount(aliceWallet, provider);
    // assert.equal(aliceBalancePost, "337000000");
    // const [, escrowBalancePost] = await readAccount(pda.htlcWalletKey, provider);
    // console.log(`${pda.htlcWalletKey} PDA htlcWALLET`);
    // console.log(`${escrowBalancePost} escrow balance`);
    // assert.equal(escrowBalancePost, "1000000000");

    const details = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
    console.log(`${details} details`);

    console.log("lamport balance of hltc after creation",
      await anchor.getProvider().connection.getBalance(pda.htlcKey));
    console.log("lamport balance of bob before redeem",
      await anchor.getProvider().connection.getBalance(bob.publicKey));
    const tx2 = await program.methods.redeem(LOCKID, SECRET, pda.htlcBump).
      accountsPartial({
        htlc: pda.htlcKey,
        userSigning: alice.publicKey,
        srcReceiver: bob.publicKey
      })
      .signers([alice])
      .rpc();
    console.log("lamport balance of alice after creation",
      await anchor.getProvider().connection.getBalance(alice.publicKey));
    console.log(`can redeem`);
    const postDetails = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
    console.log(`${postDetails} postdetails`);
    console.log("lamport balance of hltc after redeem",
      await anchor.getProvider().connection.getBalance(pda.htlcKey));
    console.log("lamport balance of bob after redeem",
      await anchor.getProvider().connection.getBalance(bob.publicKey));

    const lockId = await program.methods.getLockIdByCommitId(COMMITID).accountsPartial({ lockIdStruct: pda.lockIdStruct }).rpc();
    console.log(`${lockId} the lockId from the commitId`);

    // await wait(3000);
    // const CURTIME = new Date().getTime() / 1000;
    // console.log(`[${CURTIME * 1000}] CURRENT TIME`);
    // const tx2 = await program.methods.unlock(LOCKID, pda.htlcBump).
    //   accountsPartial({
    //     htlc: pda.htlcKey,
    //     // userSigning: alice.publicKey,
    //     userSigning: alice.publicKey,
    //     sender: alice.publicKey,
    //   })
    //   .signers([alice])
    //   .rpc();
    // console.log("lamport balance of hltc after unlock",
    //   await anchor.getProvider().connection.getBalance(pda.htlcKey));
    // // Assert that 20 tokens were sent back.
    // const [, bobBalance] = await readAccount(bobTokenAccount, provider);
    // assert.equal(bobBalance, "1000000000");

  });





  // it("can pull back funds once they are deposited", async () => {

  //   const TIME = new Date().getTime();
  //   const TIMELOC = (TIME + 2500) / 1000;
  //   const TIMELOCK = new anchor.BN(TIMELOC);
  //   console.log(`[${TIMELOC * 1000}] the Timelock`);
  //   const tx1 = await program.methods
  //     .lock(LOCKID, COMMITID, HASHLOCK, TIMELOCK, new anchor.BN(AMOUNT), DSTASSET, DSTCHAIN, DSTADDRESS, SRCASSET, bob.publicKey, pda.htlcKey, pda.htlcBump)
  //     .accountsPartial({
  //       htlc: pda.htlcKey,
  //       lockIdStruct: pda.lockIdStruct,
  //       sender: alice.publicKey,
  //     })
  //     .signers([alice])
  //     .rpc().catch(e => console.error(e));
  //   console.log(`Initialized a new Safe Pay instance. Alice will pay bob 0.01 sol`);
  //   const lockId = await program.methods.getLockIdByCommitId(COMMITID).accountsPartial({ lockIdStruct: pda.lockIdStruct }).rpc();
  //   console.log(`${lockId} the lockId from the commitId`);

  //   const details = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
  //   // Withdraw the funds back
  //   await wait(3000);
  //   const CURTIME = new Date().getTime() / 1000;
  //   console.log(`[${CURTIME * 1000}] CURRENT TIME`);
  //   const tx2 = await program.methods.unlock(LOCKID, pda.htlcBump).
  //     accountsPartial({
  //       htlc: pda.htlcKey,
  //       // userSigning: alice.publicKey,
  //       userSigning: wallet.publicKey,
  //       sender: alice.publicKey,
  //     })
  //     .signers([wallet.payer])
  //     .rpc();

  //   const postdetails = await program.methods.getLockDetails(LOCKID, pda.htlcBump).accountsPartial({ htlc: pda.htlcKey }).rpc();
  // });

});