# Audit Auctions

Variable-price security audit bidding system, designed to reduce the time it takes to obtain
an security audit based on needs, with the additional benefit of improving price transparency.

## Specification

This smart contract auctions off variably-sized audit slots to the highest bidder.

The model is that an auditing firm has 1 or more engineers who will review code,
so the collective `capacity` of the firm can be represented as the number of "engineer-weeks"
that are available. A firm with 5 engineers therefore has 5 "engineer-weeks" (aka `slots`)
that can be used each week. The firm should adjust this capacity over time to represent
capacity changing events like hiring, layoffs, vacation, etc. in order for the model to hold.
This capacity changing is set by the firm via a `schedule`, which must be locked in when bids
are finalized for those timeslots.

The audit itself is represented as a set of 1 or more `slots` worth of time, amortized
over a period of time to conduct the review. A 6 `slot` review conducted over the course
of a single week takes 6 units of capacity from the firm for that week, while a 2 week
review only takes 3 slots over two weeks of time. It is often advised that reviews with less
engineers over a greater amount of time are better than more engineers but less time. However,
review complexity also plays a factor here, usually a larger amount of engineers with a larger
amount of overall time is advised for a more complex review. This model is left out of scope
for this contract system, but should be considered when placing bids.

Pricing for these auctions should consider a minimum price that the firm might want to set on
it's time. There are periods where work might be slow, so this value is configurable, however
the firm might want to temporarily re-prioritize it's resources instead for short-term projects.
Therefore, in addition to adjusting the firm's `capacity`, there is also the `minimum_bid_price`
which is set based on market conditions and the firm's own internal business practices.

Time is of course a factor here, we want to ensure that the firm has
sufficient advanced notice for scheduling purposes so that they don't overstaff or understaff
the reviews. Therefore, we have a constant `AUCTION_CLOSE` time (set by the firm) which
allows sufficient advanced notice of what the firm is working on next. At this decision point,
any deposit left by the auction system should be considered fully bonded on the review, meaning
there is no way to retract the bid after that point. We call the standardized length of time
that the auction uses to evaluate bids using `AUCTION_CLOSE` the "epoch".

Prior to the `AUCTION_CLOSE`, there might be issues that arise (the taxonomy of which is out of
scope for our model) where the bidder might want to retract their bid. To prevent abuse of this
mechanism is "locking out" the firm's time by spamming bids by a well-resourced bidder, a conf-
igurable `withdraw_penality` is applied to bids that are withdrawn (prior to `AUCTION_CLOSE`).
Once withdrawn, the bidding resets to `minimum_bid_price` for those `slots`. The auctions are
continuously running, so bidders might want to consider withdrawing from later `slots` in the
timeline to bid on nearer `slots` that might have opened up, therefore the `withdraw_penalty`
is asymptotically increased from ~0 the closer to `auction_close` the `slots` are. This mech-
anism reduces the penalty for releasing their slots the more advance the notice they give is.
Auctions that are considered not to be "winning" their bids can withdraw at any time with no
penality.

Funding for the audit slots are paid in advance, and funds are held in escrow until
`AUCTION_CLOSE`, after which the firm is free to withdraw the funds from the contract at their
preferred frequency. It is assumed that bidders will have a legal agreement with the firm that
governs their interactions in case there is a dispute, so no consideration is given to arbitration.

Lastly, the firm has full control whether future bids will be accepted (`bids_accepted`), and
whether the firm no longer be performing it's duties (`shutdown`) in which case all bids are
withdrawable.

## Asset model

For this system, the asset we are tracking is a specific audit timeslot, which consists of:
1. The total number of `slots` (e.g. "engineer weeks") the audit will take (`total_slots`)
2. The starting date of the audit (`start_date`)
3. The durection of the audit (`duration`)
4. The total bid for the audit timeslot (`bid_amount`)
5. Whether bid has been accepted by the firm (`bid_accepted`)

We represent this bid as a non-fungible token ("Audit NFT") which is fully transferrable, such
that the NFT might trade on secondary markets, reducing overall burden on the primary auction
system. The NFTs become essentially worthless at `AUCTION_CLOSE` and have no additional rights,
unless the auditing firm deems to recognize them as a bearer asset for the audit timeslot.
Those considerations are left out of scope for this system.

Because the `capacity` of the firm and the sum of the NFT bids for specific timeslots might differ,
determining the "winning bids" for a section of time is a non-trivial path-finding problem. The
model for selecting which bids are chosen is based on what subset of bids maximizes the overall
value generated for the next epoch. However, the solution to this path-finding problem is out of
scope to this system, and the solution relies on the firm picking the subset of bids that maximizes
their own subjective assetment of what is "best" for the firm. All bids with a `start_date` that
touches `AUCTION_CLOSE` are considered "finalized" once that time is past, and cannot be modified.
Once inside that decision point, the firm will make their selection of bids and withdraw the money
that corresponds to those bids. All other bids will be unlocked for withdrawal. If the firm fails
to select a bid for that epoch, all bids will then be unlocked for withdrawal.

Bidding is conducted using a singular currency (`token`), to make evaluation of bids easy.
`token` is assumed to be an ERC20-compliant token, and cannot be reset once the contract has
been deployed. It is suggested that the firm place the contract in `shutdown` mode if the underlying
`token` contract has an issue preventing it's use as intended.
