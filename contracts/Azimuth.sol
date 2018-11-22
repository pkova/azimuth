//  the azimuth data store

pragma solidity 0.4.24;

import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

//  Azimuth: point state data contract
//
//    This contract is used for storing all data related to Azimuth points
//    and their ownership. Consider this contract the Azimuth ledger.
//
//    It also contains permissions data, which ties in to ERC721
//    functionality. Operators of an address are allowed to transfer
//    ownership of all points owned by their associated address
//    (ERC721's approveAll()). A transfer proxy is allowed to transfer
//    ownership of a single point (ERC721's approve()).
//    Separate from ERC721 are managers, assigned per point. They are
//    allowed to perform "low-impact" operations on the owner's points,
//    like configuring public keys and making escape requests.
//
//    Since data stores are difficult to upgrade, this contract contains
//    as little actual business logic as possible. Instead, the data stored
//    herein can only be modified by this contract's owner, which can be
//    changed and is thus upgradable/replacable.
//
//    This contract will be owned by the Ecliptic contract.
//
contract Azimuth is Ownable
{
  //  OwnerChanged: :point is now owned by :owner
  //
  event OwnerChanged(uint32 indexed point, address indexed owner);

  //  Activated: :point is now activate
  //
  event Activated(uint32 indexed point);

  //  Spawned: :parent has spawned :child.
  //
  event Spawned(uint32 indexed parent, uint32 child);

  //  EscapeRequested: :point has requested a new sponsor, :sponsor
  //
  event EscapeRequested(uint32 indexed point, uint32 indexed sponsor);

  //  EscapeCanceled: :point's :sponsor request was canceled or rejected
  //
  event EscapeCanceled(uint32 indexed point, uint32 indexed sponsor);

  //  EscapeAccepted: :point confirmed with a new sponsor, :sponsor
  //
  event EscapeAccepted(uint32 indexed point, uint32 indexed sponsor);

  //  LostSponsor: :point's sponsor is now refusing it service
  //
  event LostSponsor(uint32 indexed point, uint32 indexed sponsor);

  //  ChangedKeys: :point has new network public keys, :crypt and :auth
  //
  event ChangedKeys( uint32 indexed point,
                     bytes32 encryptionKey,
                     bytes32 authenticationKey,
                     uint32 cryptoSuiteVersion,
                     uint32 keyRevisionNumber );

  //  BrokeContinuity: :point has a new continuity number, :number.
  //
  event BrokeContinuity(uint32 indexed point, uint32 number);

  //  ChangedSpawnProxy: :point has a new spawn proxy
  //
  event ChangedSpawnProxy(uint32 indexed point, address indexed spawnProxy);

  //  ChangedTransferProxy: :point has a new transfer proxy
  //
  event ChangedTransferProxy( uint32 indexed point,
                              address indexed transferProxy );

  //  ChangedManagementProxy: :manager can now manage :point
  //
  event ChangedManagementProxy(uint32 indexed point, address indexed manager);

  //  ChangedVotingProxy: :voter can now vote using :point
  //
  event ChangedVotingProxy(uint32 indexed point, address indexed voter);

  //  ChangedDns: dnsDomains has been updated
  //
  event ChangedDns(string primary, string secondary, string tertiary);

  //  Size: kinds of points registered on-chain
  //
  enum Size
  {
    Galaxy,
    Star,
    Planet
  }

  //  Point: state of a point
  //
  struct Point
  {
    //  active: whether point can be used
    //
    //    false: point belongs to parent, cannot be used
    //    true: point has been, or can be, used
    //
    bool active;

    //  encryptionKey: curve25519 encryption key, or 0 for none
    //
    bytes32 encryptionKey;

    //  authenticationKey: ed25519 authentication key, or 0 for none
    //
    bytes32 authenticationKey;

    //  cryptoSuiteVersion: version of the crypto suite used for the pubkeys
    //
    uint32 cryptoSuiteVersion;

    //  keyRevisionNumber: incremented every time we change the public keys
    //
    uint32 keyRevisionNumber;

    //  continuityNumber: incremented to indicate network-side state loss
    //
    uint32 continuityNumber;

    //  spawned: for stars and galaxies, all :active children
    //
    uint32[] spawned;

    //  sponsor: the point that supports this one on the network, or,
    //           if :hasSponsor is false, the last point that supported it.
    //           (by default, the point's half-width prefix)
    //
    uint32 sponsor;

    //  hasSponsor: true if the sponsor still supports the point
    //
    bool hasSponsor;

    //  escapeRequested: true if the point has requested to change sponsors
    //
    bool escapeRequested;

    //  escapeRequestedTo: if :escapeRequested is set, new sponsor requested
    //
    uint32 escapeRequestedTo;
  }

  struct Deed
  {
    //  owner: address that owns this point
    //
    address owner;

    //  managementProxy: 0, or another address with the right to perform
    //                   low-impact, managerial tasks
    //
    address managementProxy;

    //  votingProxy: 0, or another address with the right to vote
    //
    address votingProxy;

    //  spawnProxy: 0, or another address with the right to spawn children
    //
    address spawnProxy;

    //  transferProxy: 0, or another address with the right to transfer owners
    //
    address transferProxy;
  }

  //  points: per point, general network-relevant point state
  //
  mapping(uint32 => Point) public points;

  //  rights: per point, on-chain ownership and permissions
  //
  mapping(uint32 => Deed) public rights;

  //  pointsOwnedBy: per address, list of points owned
  //
  mapping(address => uint32[]) public pointsOwnedBy;

  //  pointOwnerIndexes: per owner per point, (index + 1) in pointsOwnedBy array
  //
  //    We delete owners by moving the last entry in the array to the
  //    newly emptied slot, which is (n - 1) where n is the value of
  //    pointOwnerIndexes[owner][point].
  //
  mapping(address => mapping(uint32 => uint256)) public pointOwnerIndexes;

  //  operators: per owner, per address, has the right to transfer ownership
  //             of all the owner's points (ERC721)
  //
  mapping(address => mapping(address => bool)) public operators;

  //  managerFor: per address, the points they are managing
  //
  mapping(address => uint32[]) public managerFor;

  //  managerForIndexes: per address, per point, (index + 1) in
  //                     the managerFor array
  //
  mapping(address => mapping(uint32 => uint256)) public managerForIndexes;

  //  votingFor: per address, the points they can vote with
  //
  mapping(address => uint32[]) public votingFor;

  //  votingForIndexes: per address, per point, (index + 1) in
  //                    the votingFor array
  //
  mapping(address => mapping(uint32 => uint256)) public votingForIndexes;

  //  transferringFor: per address, the points they are transfer proxy for
  //
  mapping(address => uint32[]) public transferringFor;

  //  transferringForIndexes: per address, per point, (index + 1) in
  //                          the transferringFor array
  //
  mapping(address => mapping(uint32 => uint256)) public transferringForIndexes;

  //  spawningFor: per address, the points they are spawn proxy for
  //
  mapping(address => uint32[]) public spawningFor;

  //  spawningForIndexes: per address, per point, (index + 1) in
  //                      the spawningFor array
  //
  mapping(address => mapping(uint32 => uint256)) public spawningForIndexes;

  //  sponsoring: per point, the points they are sponsoring
  //
  mapping(uint32 => uint32[]) public sponsoring;

  //  sponsoringIndexes: per point, per point, (index + 1) in
  //                     the sponsoring array
  //
  mapping(uint32 => mapping(uint32 => uint256)) public sponsoringIndexes;

  //  escapeRequests: per point, the points they have open escape requests from
  //
  mapping(uint32 => uint32[]) public escapeRequests;

  //  escapeRequestsIndexes: per point, per point, (index + 1) in
  //                         the escapeRequests array
  //
  mapping(uint32 => mapping(uint32 => uint256)) public escapeRequestsIndexes;

  //  dnsDomains: base domains for contacting galaxies
  //
  //    dnsDomains[0] is primary, the others are used as fallbacks
  //
  string[3] public dnsDomains;

  //  constructor(): configure default dns domains
  //
  constructor()
    public
  {
    setDnsDomains("example.com", "example.com", "example.com");
  }

  //
  //  Getters, setters and checks
  //

    //  setDnsDomains(): set the base domains used for contacting galaxies
    //
    //    Note: since a string is really just a byte[], and Solidity can't
    //    work with two-dimensional arrays yet, we pass in the three
    //    domains as individual strings.
    //
    function setDnsDomains(string _primary, string _secondary, string _tertiary)
      onlyOwner
      public
    {
      dnsDomains[0] = _primary;
      dnsDomains[1] = _secondary;
      dnsDomains[2] = _tertiary;
      emit ChangedDns(_primary, _secondary, _tertiary);
    }

    //  getOwnedPoints(): return array of points that :msg.sender owns
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getOwnedPoints()
      view
      external
      returns (uint32[] ownedAzimuth)
    {
      return pointsOwnedBy[msg.sender];
    }

    //  getOwnedPointsByAddress(): return array of points that _whose owns
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getOwnedPointsByAddress(address _whose)
      view
      external
      returns (uint32[] ownedPoints)
    {
      return pointsOwnedBy[_whose];
    }

    //  getOwnedPointCount(): return length of array of points that _whose owns
    //
    function getOwnedPointCount(address _whose)
      view
      external
      returns (uint256 count)
    {
      return pointsOwnedBy[_whose].length;
    }

    //  getOwnedPointAtIndex(): get point at _index from array of points that
    //                         _whose owns
    //
    function getOwnedPointAtIndex(address _whose, uint256 _index)
      view
      external
      returns (uint32 point)
    {
      uint32[] storage owned = pointsOwnedBy[_whose];
      require(_index < owned.length);
      return owned[_index];
    }

    //  isOwner(): true if _point is owned by _address
    //
    function isOwner(uint32 _point, address _address)
      view
      external
      returns (bool result)
    {
      return (rights[_point].owner == _address);
    }

    //  getOwner(): return owner of _point
    //
    function getOwner(uint32 _point)
      view
      external
      returns (address owner)
    {
      return rights[_point].owner;
    }

    //  setOwner(): set owner of _point to _owner
    //
    //    Note: setOwner() only implements the minimal data storage
    //    logic for a transfer; the full transfer is implemented in
    //    Ecliptic.
    //
    //    Note: _owner must not be the zero address.
    //
    function setOwner(uint32 _point, address _owner)
      onlyOwner
      external
    {
      //  prevent burning of points by making zero the owner
      //
      require(0x0 != _owner);

      //  prev: previous owner, if any
      //
      address prev = rights[_point].owner;

      if (prev == _owner)
      {
        return;
      }

      //  if the point used to have a different owner, do some gymnastics to
      //  keep the list of owned points gapless.  delete this point from the
      //  list, then fill that gap with the list tail.
      //
      if (0x0 != prev)
      {
        //  i: current index in previous owner's list of owned points
        //
        uint256 i = pointOwnerIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :pointOwnerIndexes reference
        //
        uint32[] storage owner = pointsOwnedBy[prev];
        uint256 last = owner.length - 1;
        uint32 moved = owner[last];
        owner[i] = moved;
        pointOwnerIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(owner[last]);
        owner.length = last;
        pointOwnerIndexes[prev][_point] = 0;
      }

      //  update the owner list and the owner's index list
      //
      rights[_point].owner = _owner;
      pointsOwnedBy[_owner].push(_point);
      pointOwnerIndexes[_owner][_point] = pointsOwnedBy[_owner].length;
      emit OwnerChanged(_point, _owner);
    }

    function isManagementProxy(uint32 _point, address _manager)
      view
      external
      returns (bool result)
    {
      return (rights[_point].managementProxy == _manager);
    }

    function getManagementProxy(uint32 _point)
      view
      external
      returns (address manager)
    {
      return rights[_point].managementProxy;
    }

    //  canManage(): true if _who is the owner of _point,
    //               or the manager of _point's owner
    //
    function canManage(uint32 _point, address _who)
      view
      external
      returns (bool result)
    {
      Deed storage deed = rights[_point];
      return ( (0x0 != _who) &&
               ( (_who == deed.owner) ||
                 (_who == deed.managementProxy) ) );
    }

    function setManagementProxy(uint32 _point, address _manager)
      onlyOwner
      external
    {
      Deed storage deed = rights[_point];
      address prev = deed.managementProxy;
      if (prev == _manager)
      {
        return;
      }

      //  if the point used to have a different manager, do some gymnastics
      //  to keep the reverse lookup gapless.  delete the point from the
      //  old manager's list, then fill that gap with the list tail.
      //
      if (0x0 != prev)
      {
        //  i: current index in previous manager's list of managed points
        //
        uint256 i = managerForIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :managerForIndexes reference
        //
        uint32[] storage prevMfor = managerFor[prev];
        uint256 last = prevMfor.length - 1;
        uint32 moved = prevMfor[last];
        prevMfor[i] = moved;
        managerForIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevMfor[last]);
        prevMfor.length = last;
        managerForIndexes[prev][_point] = 0;
      }

      if (0x0 != _manager)
      {
        uint32[] storage mfor = managerFor[_manager];
        mfor.push(_point);
        managerForIndexes[_manager][_point] = mfor.length;
      }

      deed.managementProxy = _manager;
      emit ChangedManagementProxy(_point, _manager);
    }

    function getManagerForCount(address _manager)
      view
      external
      returns (uint256 count)
    {
      return managerFor[_manager].length;
    }

    //  getManagerFor(): get the owners _manager is a manager for
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getManagerFor(address _manager)
      view
      external
      returns (uint32[] mfor)
    {
      return managerFor[_manager];
    }

    function isVotingProxy(uint32 _point, address _voter)
      view
      external
      returns (bool result)
    {
      return (rights[_point].votingProxy == _voter);
    }

    function getVotingProxy(uint32 _point)
      view
      external
      returns (address voter)
    {
      return rights[_point].votingProxy;
    }

    //  canVoteAs(): true if _who is the owner of _point,
    //               or the voting proxy of _point's owner
    //
    function canVoteAs(uint32 _point, address _who)
      view
      external
      returns (bool result)
    {
      Deed storage deed = rights[_point];
      return ( (0x0 != _who) &&
               ( (_who == deed.owner) ||
                 (_who == deed.votingProxy) ) );
    }

    function setVotingProxy(uint32 _point, address _voter)
      onlyOwner
      external
    {
      Deed storage deed = rights[_point];
      address prev = deed.votingProxy;
      if (prev == _voter)
      {
        return;
      }

      //  if the point used to have a different voter, do some gymnastics
      //  to keep the reverse lookup gapless.  delete the point from the
      //  old voter's list, then fill that gap with the list tail.
      //
      if (0x0 != prev)
      {
        //  i: current index in previous voter's list of points it was
        //     voting for
        //
        uint256 i = votingForIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :votingForIndexes reference
        //
        uint32[] storage prevVfor = votingFor[prev];
        uint256 last = prevVfor.length - 1;
        uint32 moved = prevVfor[last];
        prevVfor[i] = moved;
        votingForIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevVfor[last]);
        prevVfor.length = last;
        votingForIndexes[prev][_point] = 0;
      }

      if (0x0 != _voter)
      {
        uint32[] storage vfor = votingFor[_voter];
        vfor.push(_point);
        votingForIndexes[_voter][_point] = vfor.length;
      }

      deed.votingProxy = _voter;
      emit ChangedVotingProxy(_point, _voter);
    }

    function getVotingForCount(address _voter)
      view
      external
      returns (uint256 count)
    {
      return votingFor[_voter].length;
    }

    //  getVotingFor(): get the owners _voter is a voter for
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getVotingFor(address _voter)
      view
      external
      returns (uint32[] vfor)
    {
      return votingFor[_voter];
    }

    //  isActive(): return true if point is active
    //
    function isActive(uint32 _point)
      view
      external
      returns (bool equals)
    {
      return points[_point].active;
    }

    //  activatePoint(): activate a point, register it as spawned by its parent
    //
    function activatePoint(uint32 _point)
      onlyOwner
      external
    {
      //  make a point active, setting its sponsor to its prefix
      //
      Point storage point = points[_point];
      require(!point.active);
      point.active = true;
      registerSponsor(_point, true, getPrefix(_point));
      emit Activated(_point);
    }

    //  registerSpawn(): add a point to its parent's list of spawned points
    //
    function registerSpawned(uint32 _point)
      onlyOwner
      external
    {
      //  if a point is its own prefix (a galaxy) then don't register it
      //
      uint32 prefix = getPrefix(_point);
      if (prefix == _point)
      {
        return;
      }

      //  register a new spawned point for the prefix
      //
      points[prefix].spawned.push(_point);
      emit Spawned(prefix, _point);
    }

    function getKeys(uint32 _point)
      view
      external
      returns (bytes32 crypt, bytes32 auth, uint32 suite, uint32 revision)
    {
      Point storage point = points[_point];
      return (point.encryptionKey,
              point.authenticationKey,
              point.cryptoSuiteVersion,
              point.keyRevisionNumber);
    }

    function getKeyRevisionNumber(uint32 _point)
      view
      external
      returns (uint32 revision)
    {
      return points[_point].keyRevisionNumber;
    }

    //  hasBeenUsed(): returns true if the point has ever been assigned keys
    //
    function hasBeenUsed(uint32 _point)
      view
      external
      returns (bool result)
    {
      return ( points[_point].keyRevisionNumber > 0 );
    }

    //  isLive(): returns true if _point currently has keys properly configured
    //
    function isLive(uint32 _point)
      view
      external
      returns (bool result)
    {
      Point storage point = points[_point];
      return ( point.encryptionKey != 0 &&
               point.authenticationKey != 0 &&
               point.cryptoSuiteVersion != 0 );
    }

    //  setKeys(): set network public keys of _point to _encryptionKey and
    //            _authenticationKey
    //
    function setKeys(uint32 _point,
                     bytes32 _encryptionKey,
                     bytes32 _authenticationKey,
                     uint32 _cryptoSuiteVersion)
      onlyOwner
      external
    {
      Point storage point = points[_point];
      if ( point.encryptionKey == _encryptionKey &&
           point.authenticationKey == _authenticationKey &&
           point.cryptoSuiteVersion == _cryptoSuiteVersion )
      {
        return;
      }

      point.encryptionKey = _encryptionKey;
      point.authenticationKey = _authenticationKey;
      point.cryptoSuiteVersion = _cryptoSuiteVersion;
      point.keyRevisionNumber++;

      emit ChangedKeys(_point,
                       _encryptionKey,
                       _authenticationKey,
                       _cryptoSuiteVersion,
                       point.keyRevisionNumber);
    }

    function getContinuityNumber(uint32 _point)
      view
      external
      returns (uint32 continuityNumber)
    {
      return points[_point].continuityNumber;
    }

    function incrementContinuityNumber(uint32 _point)
      onlyOwner
      external
    {
      Point storage point = points[_point];
      point.continuityNumber++;
      emit BrokeContinuity(_point, point.continuityNumber);
    }

    //  getSpawnCount(): return the number of children spawned by _point
    //
    function getSpawnCount(uint32 _point)
      view
      external
      returns (uint32 spawnCount)
    {
      uint256 len = points[_point].spawned.length;
      assert(len < 2**32);
      return uint32(len);
    }

    //  getSpawned(): return array of points created under _point
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getSpawned(uint32 _point)
      view
      external
      returns (uint32[] spawned)
    {
      return points[_point].spawned;
    }

    function getSponsor(uint32 _point)
      view
      external
      returns (uint32 sponsor)
    {
      return points[_point].sponsor;
    }

    function hasSponsor(uint32 _point)
      view
      external
      returns (bool has)
    {
      return points[_point].hasSponsor;
    }

    function isSponsor(uint32 _point, uint32 _sponsor)
      view
      external
      returns (bool result)
    {
      Point storage point = points[_point];
      return ( point.hasSponsor &&
               (point.sponsor == _sponsor) );
    }

    function loseSponsor(uint32 _point)
      onlyOwner
      external
    {
      Point storage point = points[_point];
      if (!point.hasSponsor)
      {
        return;
      }
      registerSponsor(_point, false, point.sponsor);
      emit LostSponsor(_point, point.sponsor);
    }

    function isEscaping(uint32 _point)
      view
      external
      returns (bool escaping)
    {
      return points[_point].escapeRequested;
    }

    function getEscapeRequest(uint32 _point)
      view
      external
      returns (uint32 escape)
    {
      return points[_point].escapeRequestedTo;
    }

    function isRequestingEscapeTo(uint32 _point, uint32 _sponsor)
      view
      public
      returns (bool equals)
    {
      Point storage point = points[_point];
      return (point.escapeRequested && (point.escapeRequestedTo == _sponsor));
    }

    function setEscapeRequest(uint32 _point, uint32 _sponsor)
      onlyOwner
      external
    {
      if (isRequestingEscapeTo(_point, _sponsor))
      {
        return;
      }
      registerEscapeRequest(_point, true, _sponsor);
      emit EscapeRequested(_point, _sponsor);
    }

    function cancelEscape(uint32 _point)
      onlyOwner
      external
    {
      Point storage point = points[_point];
      if (!point.escapeRequested)
      {
        return;
      }
      uint32 request = point.escapeRequestedTo;
      registerEscapeRequest(_point, false, 0);
      emit EscapeCanceled(_point, request);
    }

    //  doEscape(): perform the requested escape
    //
    function doEscape(uint32 _point)
      onlyOwner
      external
    {
      Point storage point = points[_point];
      require(point.escapeRequested);
      registerSponsor(_point, true, point.escapeRequestedTo);
      registerEscapeRequest(_point, false, 0);
      emit EscapeAccepted(_point, point.sponsor);
    }

    function getSponsoringCount(uint32 _sponsor)
      view
      external
      returns (uint256 count)
    {
      return sponsoring[_sponsor].length;
    }

    //  getSponsoring(): get the points _sponsor is a sponsor for
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getSponsoring(uint32 _sponsor)
      view
      external
      returns (uint32[] sponsees)
    {
      return sponsoring[_sponsor];
    }

    function getEscapeRequestsCount(uint32 _sponsor)
      view
      external
      returns (uint256 count)
    {
      return escapeRequests[_sponsor].length;
    }

    //  getEscapeRequests(): get the points _sponsor has received escape
    //                       requests from
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getEscapeRequests(uint32 _sponsor)
      view
      external
      returns (uint32[] requests)
    {
      return escapeRequests[_sponsor];
    }

    function isSpawnProxy(uint32 _point, address _spawner)
      view
      external
      returns (bool result)
    {
      return (rights[_point].spawnProxy == _spawner);
    }

    function getSpawnProxy(uint32 _point)
      view
      external
      returns (address spawnProxy)
    {
      return rights[_point].spawnProxy;
    }

    //  canSpawnAs(): true if _who is the owner or spawn proxy of _point
    //
    function canSpawnAs(uint32 _point, address _who)
      view
      external
      returns (bool result)
    {
      Deed storage deed = rights[_point];
      return ( (0x0 != _who) &&
               ( (_who == deed.owner) ||
                 (_who == deed.spawnProxy) ) );
    }

    function setSpawnProxy(uint32 _point, address _spawner)
      onlyOwner
      external
    {
      Deed storage deed = rights[_point];
      address prev = deed.spawnProxy;
      if (prev == _spawner)
      {
        return;
      }

      //  if the point used to have a different spawn proxy, do some
      //  gymnastics to keep the reverse lookup gapless.  delete the point
      //  from the old proxy's list, then fill that gap with the list tail.
      //
      if (0x0 != prev)
      {
        //  i: current index in previous proxy's list of spawning points
        //
        uint256 i = spawningForIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :spawningForIndexes reference
        //
        uint32[] storage prevSfor = spawningFor[prev];
        uint256 last = prevSfor.length - 1;
        uint32 moved = prevSfor[last];
        prevSfor[i] = moved;
        spawningForIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevSfor[last]);
        prevSfor.length = last;
        spawningForIndexes[prev][_point] = 0;
      }

      if (0x0 != _spawner)
      {
        uint32[] storage sfor = spawningFor[_spawner];
        sfor.push(_point);
        spawningForIndexes[_spawner][_point] = sfor.length;
      }

      deed.spawnProxy = _spawner;
      emit ChangedSpawnProxy(_point, _spawner);
    }

    function getSpawningForCount(address _proxy)
      view
      external
      returns (uint256 count)
    {
      return spawningFor[_proxy].length;
    }

    //  getSpawningFor(): get the points _proxy is a spawn proxy for
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getSpawningFor(address _proxy)
      view
      external
      returns (uint32[] sfor)
    {
      return spawningFor[_proxy];
    }

    function isTransferProxy(uint32 _point, address _transferrer)
      view
      external
      returns (bool result)
    {
      return (rights[_point].transferProxy == _transferrer);
    }

    function getTransferProxy(uint32 _point)
      view
      external
      returns (address transferProxy)
    {
      return rights[_point].transferProxy;
    }

    //  canTransfer(): true if _who is the owner or transfer proxy of _point,
    //                 or is an operator for _point's current owner
    //
    function canTransfer(uint32 _point, address _who)
      view
      external
      returns (bool result)
    {
      Deed storage deed = rights[_point];
      return ( (0x0 != _who) &&
               ( (_who == deed.owner) ||
                 (_who == deed.transferProxy) ||
                 operators[deed.owner][_who] ) );
    }

    //  setTransferProxy(): configure _transferrer as transfer proxy for _point
    //
    function setTransferProxy(uint32 _point, address _transferrer)
      onlyOwner
      external
    {
      Deed storage deed = rights[_point];
      address prev = deed.transferProxy;
      if (prev == _transferrer)
      {
        return;
      }

      //  if the point used to have a different transfer proxy, do some
      //  gymnastics to keep the reverse lookup gapless.  delete the point
      //  from the old proxy's list, then fill that gap with the list tail.
      //
      if (0x0 != prev)
      {
        //  i: current index in previous proxy's list of transferable points
        //
        uint256 i = transferringForIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :transferringForIndexes reference
        //
        uint32[] storage prevTfor = transferringFor[prev];
        uint256 last = prevTfor.length - 1;
        uint32 moved = prevTfor[last];
        prevTfor[i] = moved;
        transferringForIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevTfor[last]);
        prevTfor.length = last;
        transferringForIndexes[prev][_point] = 0;
      }

      if (0x0 != _transferrer)
      {
        uint32[] storage tfor = transferringFor[_transferrer];
        tfor.push(_point);
        transferringForIndexes[_transferrer][_point] = tfor.length;
      }

      deed.transferProxy = _transferrer;
      emit ChangedTransferProxy(_point, _transferrer);
    }

    function getTransferringForCount(address _proxy)
      view
      external
      returns (uint256 count)
    {
      return transferringFor[_proxy].length;
    }

    //  getTransferringFor(): get the points _proxy is a transfer proxy for
    //
    //    Note: only useful for clients, as Solidity does not currently
    //    support returning dynamic arrays.
    //
    function getTransferringFor(address _proxy)
      view
      external
      returns (uint32[] tfor)
    {
      return transferringFor[_proxy];
    }

    function isOperator(address _owner, address _operator)
      view
      external
      returns (bool result)
    {
      return operators[_owner][_operator];
    }

    //  setOperator(): dis/allow _operator to transfer ownership of all points
    //                 owned by _owner
    //
    //    operators are part of the ERC721 standard
    //
    function setOperator(address _owner, address _operator, bool _approved)
      onlyOwner
      external
    {
      operators[_owner][_operator] = _approved;
    }

  //
  //  Utility functions
  //

    //  registerSponsor(): set the sponsorship state of _point and update the
    //                reverse lookup for sponsors
    //
    function registerSponsor(uint32 _point, bool _hasSponsor, uint32 _sponsor)
      internal
    {
      Point storage point = points[_point];
      bool had = point.hasSponsor;
      uint32 prev = point.sponsor;
      if ( (!had && !_hasSponsor) ||
           (had && _hasSponsor && prev == _sponsor) )
      {
        return;
      }

      //  if the point used to have a different sponsor, do some gymnastics
      //  to keep the reverse lookup gapless.  delete the point from the old
      //  sponsor's list, then fill that gap with the list tail.
      //
      if (had)
      {
        //  i: current index in previous sponsor's list of sponsored points
        //
        uint256 i = sponsoringIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :sponsoringIndexes reference
        //
        uint32[] storage prevSponsoring = sponsoring[prev];
        uint256 last = prevSponsoring.length - 1;
        uint32 moved = prevSponsoring[last];
        prevSponsoring[i] = moved;
        sponsoringIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevSponsoring[last]);
        prevSponsoring.length = last;
        sponsoringIndexes[prev][_point] = 0;
      }

      if (_hasSponsor)
      {
        uint32[] storage newSponsoring = sponsoring[_sponsor];
        newSponsoring.push(_point);
        sponsoringIndexes[_sponsor][_point] = newSponsoring.length;
      }

      point.sponsor = _sponsor;
      point.hasSponsor = _hasSponsor;
    }

    //  registerEscapeRequest(): set the escape state of _point and update the
    //                           reverse lookup for sponsors
    //
    function registerEscapeRequest( uint32 _point,
                                    bool _isEscaping, uint32 _sponsor )
      internal
    {
      Point storage point = points[_point];
      bool was = point.escapeRequested;
      uint32 prev = point.escapeRequestedTo;
      if ( (!was && !_isEscaping) ||
           (was && _isEscaping && prev == _sponsor) )
      {
        return;
      }

      //  if the point used to have a different request, do some gymnastics
      //  to keep the reverse lookup gapless.  delete the point from the old
      //  sponsor's list, then fill that gap with the list tail.
      //
      if (was)
      {
        //  i: current index in previous sponsor's list of sponsored points
        //
        uint256 i = escapeRequestsIndexes[prev][_point];

        //  we store index + 1, because 0 is the solidity default value
        //
        assert(i > 0);
        i--;

        //  copy the last item in the list into the now-unused slot,
        //  making sure to update its :escapeRequestsIndexes reference
        //
        uint32[] storage prevRequests = escapeRequests[prev];
        uint256 last = prevRequests.length - 1;
        uint32 moved = prevRequests[last];
        prevRequests[i] = moved;
        escapeRequestsIndexes[prev][moved] = i + 1;

        //  delete the last item
        //
        delete(prevRequests[last]);
        prevRequests.length = last;
        escapeRequestsIndexes[prev][_point] = 0;
      }

      if (_isEscaping)
      {
        uint32[] storage newRequests = escapeRequests[_sponsor];
        newRequests.push(_point);
        escapeRequestsIndexes[_sponsor][_point] = newRequests.length;
      }

      point.escapeRequestedTo = _sponsor;
      point.escapeRequested = _isEscaping;
    }

    //  getPrefix(): compute prefix parent of _point
    //
    function getPrefix(uint32 _point)
      pure
      public
      returns (uint16 parent)
    {
      if (_point < 0x10000)
      {
        return uint16(_point % 0x100);
      }
      return uint16(_point % 0x10000);
    }

    //  getPointSize(): return the size of _point
    //
    function getPointSize(uint32 _point)
      external
      pure
      returns (Size _size)
    {
      if (_point < 0x100) return Size.Galaxy;
      if (_point < 0x10000) return Size.Star;
      return Size.Planet;
    }
}
