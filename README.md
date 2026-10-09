# ZipBNB contracts

**Move with privacy. Speak with purpose.** · [zipbnb.cash](https://zipbnb.cash) · [App](https://app.zipbnb.cash) · [X](https://x.com/zipbnb)

ZipBNB lets you move BNB, USDT and ZBNB on BNB Chain privately, and burn ZBNB to publish in a public message board
(the Book). It is built on [0xbow's Privacy Pools](https://github.com/0xbow-io/privacy-pools-core): a deposit
("zip") becomes a private note, and a zero-knowledge proof lets you withdraw it ("unzip") to any address without
linking the two. Deposits are screened before they can be withdrawn privately; a deposit that is not approved can
always be withdrawn back to the address it came from (ragequit).

This repository holds **the contracts ZipBNB wrote**, exactly as deployed. The pools, the Entrypoint and the proof
verifiers are 0xbow's audited code, used unmodified.

## Contracts

| File | What it does |
| --- | --- |
| `control/PostmanGate.sol` | The only way an approval list (association-set root) reaches the Entrypoint. The operator posts; the Safe can pause it, post a root itself, or replace the operator at once. |
| `control/PoolAdmin.sol` | The Safe's fast lane: add a pool, wind one down, remove a wound-down one, set a pool's minimum and deposit fee (up to 1%), and collect deposit fees to the Safe. Nothing else. |
| `spend/Changer.sol` | Unzip as a different asset in one step (for example USDT → BNB), through PancakeSwap V3. |
| `spend/venues/PancakeV3Venue.sol` | The Changer's connection to PancakeSwap V3. |
| `spend/Doorstep.sol` | The Book: burn ZBNB to publish a message, publicly or anonymously from a note, optionally with a gift at someone's door. |
| `core/Upstream.sol` | Pulls 0xbow's unmodified Entrypoint and pools into the build, so the deployment uses exactly the audited code. |
| `interfaces/` | The interfaces of the contracts above. |

## Deployed on BNB Chain (chain 56)

Deployed at block 126502306. Every address links to its source on BscScan.

| Contract | Address |
| --- | --- |
| Entrypoint (proxy; users and the app call this) | [`0xb83B19c94f912FAe2EC42FCa0839A26b11325BE7`](https://bscscan.com/address/0xb83B19c94f912FAe2EC42FCa0839A26b11325BE7#code) |
| Entrypoint implementation (0xbow, unmodified) | [`0x3D1e568dabC2C17F9A2F9AbbAf68894055d884C5`](https://bscscan.com/address/0x3D1e568dabC2C17F9A2F9AbbAf68894055d884C5#code) |
| Timelock (48 h, OpenZeppelin) | [`0xd0D9eE9410F9ce4512D57a06D04964c0998451A3`](https://bscscan.com/address/0xd0D9eE9410F9ce4512D57a06D04964c0998451A3#code) |
| PostmanGate | [`0x78F63562Ef948209d949BFf6a4f0B4128405779A`](https://bscscan.com/address/0x78F63562Ef948209d949BFf6a4f0B4128405779A#code) |
| PoolAdmin | [`0xD2f941F2eD0De58359971C70740FCE79fF3bD45c`](https://bscscan.com/address/0xD2f941F2eD0De58359971C70740FCE79fF3bD45c#code) |
| ZBNB pool (0xbow) | [`0xC9A659b408D77475A0df75495a488a3C74E6dd4f`](https://bscscan.com/address/0xC9A659b408D77475A0df75495a488a3C74E6dd4f#code) |
| BNB pool (0xbow) | [`0x65093b05020870b8B2888a559560eCE921eDFbCC`](https://bscscan.com/address/0x65093b05020870b8B2888a559560eCE921eDFbCC#code) |
| USDT pool (0xbow) | [`0x330d9D450837db2265f195E149615Fa21c3c79B4`](https://bscscan.com/address/0x330d9D450837db2265f195E149615Fa21c3c79B4#code) |
| Doorstep | [`0xb5E903963FD530A06E88972D742e1F3BCDA6b369`](https://bscscan.com/address/0xb5E903963FD530A06E88972D742e1F3BCDA6b369#code) |
| Changer | [`0x23Ff1bC520C6e6c1aDC7C3912e537BC56D0FBDDE`](https://bscscan.com/address/0x23Ff1bC520C6e6c1aDC7C3912e537BC56D0FBDDE#code) |
| PancakeV3Venue | [`0xE0A651f0992bEDFb4C0Aac060112f35D208A5029`](https://bscscan.com/address/0xE0A651f0992bEDFb4C0Aac060112f35D208A5029#code) |

ZBNB token: [`0x4628076022bdecc04a4e52d10ffb3aba10745555`](https://bscscan.com/token/0x4628076022bdecc04a4e52d10ffb3aba10745555)

## Who controls what

- **The pools cannot be upgraded**, and **ragequit always works**: a depositor can always take an unapproved deposit
  back, whatever the operators do.
- A **Safe** (multi-signature wallet) controls PostmanGate and PoolAdmin, and is the only proposer and executor of
  the **48-hour timelock**, which owns the Entrypoint. Upgrades, role changes and fees above 1% wait 48 hours in
  public before they take effect.
- Doorstep, Changer and PancakeV3Venue have **no owner and no admin**.
- Fees: a 0.5% deposit fee (held by the Entrypoint, collected only to the Safe) and a relay fee (currently 1%, capped
  at 3% by the contracts) paid to the relayer that submits a private withdrawal. ZBNB burned in the Book is destroyed.

## Building

These files compile with Solidity 0.8.28 (optimizer on, 10,000 runs, no metadata hash) against
[0xbow's privacy-pools-core v1.3.0](https://github.com/0xbow-io/privacy-pools-core) and OpenZeppelin Contracts. The
exact compiler input for every contract is the verified source on BscScan.

## Licences

Each file states its licence in its first line (MIT, or Apache-2.0 for `spend/Doorstep.sol`). See [NOTICE](NOTICE)
for credits.

## Security

Found a problem? Please report it privately to the ZipBNB team (X: [@zipbnb](https://x.com/zipbnb)) rather than in a
public issue.
