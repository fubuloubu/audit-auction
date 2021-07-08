# @version 0.2.12

"""
@dev Audit Timeslot Auction contract
"""

from vyper.interfaces import ERC20

# The ERC20 token used for bids
token: public(ERC20)

# State variables for tracking epochs
first_epoch: public(uint256)
last_epoch: public(uint256)
current_week_id: public(uint256)


#### Constructor ####

@external
def __init__(token: address, first_epoch: uint256):
    """
    @dev Contract constructor.
    @param token The accepted token for bidding
    """

    self.token = ERC20(token)

    # Setup epochs
    assert block.timestamp <= first_epoch
    self.first_epoch = first_epoch
    self.last_epoch = first_epoch - EPOCH_LENGTH

    # init ERC-165 support
    self.supportsInterface[ERC165_INTERFACE_ID] = True
    self.supportsInterface[ERC721_INTERFACE_ID] = True


#### ERC-165 Implementation ####

# @dev Mapping of interface id to bool about whether or not it's supported
supportsInterface: public(HashMap[bytes32, bool])

# @dev ERC165 interface ID of ERC165
ERC165_INTERFACE_ID: constant(bytes32) = \
    0x0000000000000000000000000000000000000000000000000000000001ffc9a7

# @dev ERC165 interface ID of ERC721
ERC721_INTERFACE_ID: constant(bytes32) = \
    0x0000000000000000000000000000000000000000000000000000000080ac58cd



#### Special Roles #####

# The auditing firm
# NOTE: keys can be upgraded via 2-phase commit
admin: public(address)
pending_admin: address


@external
def set_admin(new_admin: address):
    """
    @dev Set a new key for the admin role (starts 2-phase commit)
    @param new_admin The address of the new admin key
    """
    assert msg.sender == self.admin
    self.pending_admin = new_admin


@external
def accept_admin():
    """
    @dev Accept the new admin role (comples 2-phase commit)
    """
    assert msg.sender == self.pending_admin
    self.admin = msg.sender  # NOTE: Constrained by above


# Place the contract into "hard shutdown mode", allowing all bids to be withdrawn
shutdown: public(bool)


@external
def set_shutdown():
    assert msg.sender == self.admin
    self.shutdown = True


# Place the contract into "soft shutdown mode", no longer accepting new bids
bids_accepted: public(bool)


@external
def disable_bids():
    assert msg.sender == self.admin
    self.bids_accepted = True


# week_id => number of engineer-weeks available
capacity: public(HashMap[uint256, uint256])


@external
def set_capacity(week_ids: uint256[52], capacities: uint256[52]):
    assert msg.sender == self.admin

    current_week_id: uint256 = self.current_week_id
    for idx in range(52):
        assert week_ids[idx] > current_week_id
        self.capacity[week_ids[idx]] = capacities[idx]



# Minimum accepted bid per slot
min_bid: public(uint256)


@external
def set_min_bid(min_bid: uint256):
    assert msg.sender == self.admin
    self.min_bid = min_bid


#### ERC-721 Implementation ####
from vyper.interfaces import ERC721

implements: ERC721

# Interface for the contract called by safeTransferFrom()
interface ERC721Receiver:
    def onERC721Received(
            _operator: address,
            _from: address,
            _tokenId: uint256,
            _data: Bytes[1024]
        ) -> bytes32: view


# @dev Emits when ownership of any NFT changes by any mechanism. This event emits when NFTs are
#      created (`from` == 0) and destroyed (`to` == 0). Exception: during contract creation, any
#      number of NFTs may be created and assigned without emitting Transfer. At the time of any
#      transfer, the approved address for that NFT (if any) is reset to none.
# @param _from Sender of NFT (if address is zero address it indicates token creation).
# @param _to Receiver of NFT (if address is zero address it indicates token destruction).
# @param _tokenId The NFT that got transfered.
event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    tokenId: indexed(uint256)

# @dev This emits when the approved address for an NFT is changed or reaffirmed. The zero
#      address indicates there is no approved address. When a Transfer event emits, this also
#      indicates that the approved address for that NFT (if any) is reset to none.
# @param _owner Owner of NFT.
# @param _approved Address that we are approving.
# @param _tokenId NFT which we are approving.
event Approval:
    owner: indexed(address)
    approved: indexed(address)
    tokenId: indexed(uint256)

# @dev This emits when an operator is enabled or disabled for an owner. The operator can manage
#      all NFTs of the owner.
# @param _owner Owner of NFT.
# @param _operator Address to which we are setting operator rights.
# @param _approved Status of operator rights(true if operator rights are given and false if
# revoked).
event ApprovalForAll:
    owner: indexed(address)
    operator: indexed(address)
    approved: bool


# @dev Mapping from NFT ID to the address that owns it.
ownerOf: public(HashMap[uint256, address])

# @dev Mapping from NFT ID to approved address.
getApproved: public(HashMap[uint256, address])

# @dev Mapping from owner address to count of their tokens.
balanceOf: public(HashMap[address, uint256])

# @dev Mapping from owner address to mapping of operator addresses.
isApprovedForAll: public(HashMap[address, HashMap[address, bool]])


### TRANSFER FUNCTION HELPERS ###

@view
@internal
def _isApprovedOrOwner(_spender: address, _tokenId: uint256) -> bool:
    """
    @dev Returns whether the given spender can transfer a given token ID
    @param spender address of the spender to query
    @param tokenId uint256 ID of the token to be transferred
    @return bool whether the msg.sender is approved for the given token ID,
        is an operator of the owner, or is the owner of the token
    """
    owner: address = self.ownerOf[_tokenId]
    spenderIsOwner: bool = owner == _spender
    spenderIsApproved: bool = _spender == self.getApproved[_tokenId]
    spenderIsApprovedForAll: bool = (self.isApprovedForAll[owner])[_spender]
    return (spenderIsOwner or spenderIsApproved) or spenderIsApprovedForAll


@internal
def _addTokenTo(_to: address, _tokenId: uint256):
    """
    @dev Add a NFT to a given address
         Throws if `_tokenId` is owned by someone.
    """
    # Throws if `_tokenId` is owned by someone
    assert self.ownerOf[_tokenId] == ZERO_ADDRESS
    # Change the owner
    self.ownerOf[_tokenId] = _to
    # Change count tracking
    self.balanceOf[_to] += 1


@internal
def _removeTokenFrom(_from: address, _tokenId: uint256):
    """
    @dev Remove a NFT from a given address
         Throws if `_from` is not the current owner.
    """
    # Throws if `_from` is not the current owner
    assert self.ownerOf[_tokenId] == _from
    # Change the owner
    self.ownerOf[_tokenId] = ZERO_ADDRESS
    # Change count tracking
    self.balanceOf[_from] -= 1


@internal
def _clearApproval(_owner: address, _tokenId: uint256):
    """
    @dev Clear an approval of a given address
         Throws if `_owner` is not the current owner.
    """
    # Throws if `_owner` is not the current owner
    assert self.ownerOf[_tokenId] == _owner
    if self.getApproved[_tokenId] != ZERO_ADDRESS:
        # Reset approvals
        self.getApproved[_tokenId] = ZERO_ADDRESS


@internal
def _transferFrom(_from: address, _to: address, _tokenId: uint256, _sender: address):
    """
    @dev Exeute transfer of a NFT.
         Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
         address for this NFT. (NOTE: `msg.sender` not allowed in private function so pass `_sender`.)
         Throws if `_to` is the zero address.
         Throws if `_from` is not the current owner.
         Throws if `_tokenId` is not a valid NFT.
    """
    # Check requirements
    assert self._isApprovedOrOwner(_sender, _tokenId)
    # Throws if `_to` is the zero address
    assert _to != ZERO_ADDRESS
    # Clear approval. Throws if `_from` is not the current owner
    self._clearApproval(_from, _tokenId)
    # Remove NFT. Throws if `_tokenId` is not a valid NFT
    self._removeTokenFrom(_from, _tokenId)
    # Add NFT
    self._addTokenTo(_to, _tokenId)
    # Log the transfer
    log Transfer(_from, _to, _tokenId)


### TRANSFER FUNCTIONS ###

@external
def transferFrom(_from: address, _to: address, _tokenId: uint256):
    """
    @dev Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
         address for this NFT.
         Throws if `_from` is not the current owner.
         Throws if `_to` is the zero address.
         Throws if `_tokenId` is not a valid NFT.
    @notice The caller is responsible to confirm that `_to` is capable of receiving NFTs or else
            they maybe be permanently lost.
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer.
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)


@external
def safeTransferFrom(
        _from: address,
        _to: address,
        _tokenId: uint256,
        _data: Bytes[1024]=b""
    ):
    """
    @dev Transfers the ownership of an NFT from one address to another address.
         Throws unless `msg.sender` is the current owner, an authorized operator, or the
         approved address for this NFT.
         Throws if `_from` is not the current owner.
         Throws if `_to` is the zero address.
         Throws if `_tokenId` is not a valid NFT.
         If `_to` is a smart contract, it calls `onERC721Received` on `_to` and throws if
         the return value is not `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`.
         NOTE: bytes4 is represented by bytes32 with padding
    @param _from The current owner of the NFT.
    @param _to The new owner.
    @param _tokenId The NFT to transfer.
    @param _data Additional data with no specified format, sent in call to `_to`.
    """
    self._transferFrom(_from, _to, _tokenId, msg.sender)
    if _to.is_contract: # check if `_to` is a contract address
        returnValue: bytes32 = ERC721Receiver(_to).onERC721Received(msg.sender, _from, _tokenId, _data)
        # Throws if transfer destination is a contract which does not implement 'onERC721Received'
        assert returnValue == method_id("onERC721Received(address,address,uint256,bytes)", output_type=bytes32)


@external
def approve(_approved: address, _tokenId: uint256):
    """
    @dev Set or reaffirm the approved address for an NFT. The zero address indicates there is no approved address.
         Throws unless `msg.sender` is the current NFT owner, or an authorized operator of the current owner.
         Throws if `_tokenId` is not a valid NFT. (NOTE: This is not written the EIP)
         Throws if `_approved` is the current owner. (NOTE: This is not written the EIP)
    @param _approved Address to be approved for the given NFT ID.
    @param _tokenId ID of the token to be approved.
    """
    owner: address = self.ownerOf[_tokenId]
    # Throws if `_tokenId` is not a valid NFT
    assert owner != ZERO_ADDRESS
    # Throws if `_approved` is the current owner
    assert _approved != owner
    # Check requirements
    senderIsOwner: bool = self.ownerOf[_tokenId] == msg.sender
    senderIsApprovedForAll: bool = (self.isApprovedForAll[owner])[msg.sender]
    assert (senderIsOwner or senderIsApprovedForAll)
    # Set the approval
    self.getApproved[_tokenId] = _approved
    log Approval(owner, _approved, _tokenId)


@external
def setApprovalForAll(_operator: address, _approved: bool):
    """
    @dev Enables or disables approval for a third party ("operator") to manage all of
         `msg.sender`'s assets. It also emits the ApprovalForAll event.
         Throws if `_operator` is the `msg.sender`. (NOTE: This is not written the EIP)
    @notice This works even if sender doesn't own any tokens at the time.
    @param _operator Address to add to the set of authorized operators.
    @param _approved True if the operators is approved, false to revoke approval.
    """
    # Throws if `_operator` is the `msg.sender`
    assert _operator != msg.sender
    self.isApprovedForAll[msg.sender][_operator] = _approved
    log ApprovalForAll(msg.sender, _operator, _approved)


#### Auction System ####

# Auctions close this amount of weeks prior to starting
ONE_WEEK: constant(uint256) = 7 * 24 * 60 * 60
EPOCH_LENGTH: constant(uint256) = 2 * ONE_WEEK
# Maximum number of weeks to book at a time
MAX_WEEKS: constant(uint256) = 6

# Penalty calc constants
MAX_PENALTY: constant(uint256) = 1_500  # 15%
MAX_BPS: constant(uint256) = 10_000  # 100%
# NOTE: This parameter must be tuned for the appropiate decay factor
DECAY_CONSTANT: constant(uint256) = 2 ** 32


struct Bid:
    num_slots: uint256
    start_date: uint256
    duration: uint256
    amount: uint256
    accepted: bool


# tokenId => Bid
bids: public(HashMap[uint256, Bid])
MAX_BIDS: constant(uint256) = 20  # Maximum number of bids to consider when accepting


@internal
def _compute_tokenId(bid: Bid) -> uint256:
    tokenId: bytes32 = keccak256(
        concat(
            convert(bid.num_slots, bytes32),
            convert(bid.start_date, bytes32),
            convert(bid.duration, bytes32),
            # NOTE: `bid.amount`, `bid.accepted`, and current owner not considered for Token ID
        )
    )

    return convert(tokenId, uint256)


@internal
def _ceil_div(a: uint256, b: uint256) -> uint256:
    # The following lines are basically `math.ceil()`
    c: uint256 = a / b

    # This condition executes IFF there is some remainder value
    if a % b > 0:
        c += 1

    return c


@external
def bid(num_slots: uint256, start_date: uint256, duration: uint256, bid_amount: uint256) -> bool:
    """
    @dev Function to bid on slots. The TokenID for the bid is computed dynamically based on the bid
        Throws if `start_date` is within the current epoch
        If trying to outbid another bidder, must be higher than their bid
        Throws if this contract is not approved to take `bid_amount` from caller
    @param num_slots The total number of slots (e.g. "engineer weeks") the audit will take
    @param start_date The starting date of the audit
    @param duration The durection of the audit
    @param bid_amount The total bid for the audit timeslot
    @return A boolean that indicates if the operation was successful.
    """
    # Ensure bid is for open epochs
    assert start_date >= block.timestamp + EPOCH_LENGTH
    assert duration % ONE_WEEK == 0

    # Ensure bid meets minimum requirements
    assert bid_amount / num_slots >= self.min_bid
    assert self.token.transferFrom(msg.sender, self, bid_amount)

    # Make sure we don't bid for more than the total weeks per appointment
    num_weeks: uint256 = duration / ONE_WEEK
    assert num_weeks <= MAX_WEEKS

    # Make sure we don't overuse resources for the weeks we want
    resources_needed: uint256 = self._ceil_div(num_slots, num_weeks)
    start_week_id: uint256 = (start_date - self.first_epoch) / ONE_WEEK
    for week_id in range(start_week_id, start_week_id + MAX_WEEKS):
        if num_weeks == 0:
            break  # Ran out of weeks to process

        assert self.capacity[week_id] >= resources_needed
        num_weeks -= 1

    bid: Bid = Bid({
        num_slots: num_slots,
        start_date: start_date,
        duration: duration,
        amount: bid_amount,
        accepted: False,
    })
    tokenId: uint256 = self._compute_tokenId(bid)

    current_owner: address = self.ownerOf[tokenId]
    if current_owner != ZERO_ADDRESS:
        # NFT already minted, compare bid
        current_bid: uint256 = self.bids[tokenId].amount
        assert bid_amount > current_bid

        # Refund bidder
        assert self.token.transfer(current_owner, current_bid)

        # Update ownership
        # NOTE: This ensures that `_addTokenTo` doesn't fail by reseting ownership
        self._clearApproval(current_owner, tokenId)
        self._removeTokenFrom(current_owner, tokenId)

    # else: Create new bid (mints new NFT)

    self._addTokenTo(msg.sender, tokenId)
    # NOTE: if `current_owner` is the null address, this appears as a "mint"
    log Transfer(current_owner, msg.sender, tokenId)
    return True


@external
def withdraw_bid(tokenId: uint256) -> bool:
    """
    @dev Burns a specific ERC721 token.
         Throws unless `msg.sender` is the current owner, an authorized operator, or the approved
         address for this NFT.
         Throws if `_tokenId` is not a valid NFT.
         Throws if trying to withdraw within the epoch period
         Throws if trying to withdraw after epoch is over but bid was approved
         A penalty is applied if withdrawing the bid prior to the bid epoch starting
    @param tokenId uint256 id of the ERC721 token to be burned.
    """

    assert self._isApprovedOrOwner(msg.sender, tokenId)
    owner: address = self.ownerOf[tokenId]
    # Throws if `tokenId` is not a valid NFT
    assert owner != ZERO_ADDRESS

    bid: Bid = self.bids[tokenId]
    epoch_over: bool = bid.start_date < block.timestamp
    # Must either be prior to epoch, or after (but bid cannot be accepted during epoch)
    assert (
        # Bidding hasn't closed
        bid.start_date >= block.timestamp + EPOCH_LENGTH
        # Epoch has expired and bid was not accepted
        or (epoch_over and not bid.accepted)
    )

    # Check to see if the resources has changed and we can withdraw our bid without penalty
    num_weeks: uint256 = bid.duration / ONE_WEEK
    resources_needed: uint256 = self._ceil_div(bid.num_slots, num_weeks)
    start_week_id: uint256 = (bid.start_date - self.first_epoch) / ONE_WEEK

    resources_overused: bool = False
    for week_id in range(start_week_id, start_week_id + MAX_WEEKS):
        if num_weeks == 0:
            break  # Ran out of weeks to process

        if self.capacity[week_id] < resources_needed:
            resources_overused = True
            break

        num_weeks -= 1

    # Admin has raised their minimum
    bid_insufficient: bool = bid.amount / bid.num_slots < self.min_bid

    # Refund bid w/ penalties applied (if withdrawn prior to epoch starting)
    refund: uint256 = bid.amount
    if not (epoch_over or resources_overused or bid_insufficient):
        # Caclulate maximum penalty
        penalty: uint256 = MAX_PENALTY * bid.amount / MAX_BPS

        # Adjust penality by time to epoch start
        time_to_epoch: uint256 = bid.start_date + EPOCH_LENGTH - block.timestamp
        if time_to_epoch > 0:
            penalty += DECAY_CONSTANT
            penalty /= time_to_epoch

        refund -= penalty

    self.token.transfer(owner, refund)

    # Remove our bid by deleting the NFT
    self._clearApproval(owner, tokenId)
    self._removeTokenFrom(owner, tokenId)
    log Transfer(owner, ZERO_ADDRESS, tokenId)
    return True


@external
def select_bids(tokenIds: uint256[MAX_BIDS]):
    assert msg.sender == self.admin
    epoch_end: uint256 = self.last_epoch + EPOCH_LENGTH
    assert block.timestamp < epoch_end

    week_id: uint256 = (epoch_end - self.first_epoch) / EPOCH_LENGTH
    capacity: uint256 = self.capacity[week_id]

    total_resources_used: uint256 = 0
    total_epoch_bid_amount: uint256 = 0
    for tokenId in tokenIds:
        # Bid is not accepted
        assert not self.bids[tokenId].accepted
        self.bids[tokenId].accepted = True

        # Bid is in epoch
        bid_start: uint256 = self.bids[tokenId].start_date
        assert bid_start > block.timestamp
        assert bid_start <= epoch_end

        # Ensure we are not overusing resources
        total_resources_used += self._ceil_div(
            self.bids[tokenId].num_slots,
            self.bids[tokenId].duration / ONE_WEEK,
        )
        assert total_resources_used <= capacity

        # Add bid amount to sum
        total_epoch_bid_amount += self.bids[tokenId].amount

    self.token.transfer(self.admin, total_epoch_bid_amount)

    # Advance the epoch to next
    self.last_epoch += EPOCH_LENGTH
    self.current_week_id += 1
