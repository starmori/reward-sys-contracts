// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IJackPotLottery.sol";
import "./DVoucherNFT.sol";

contract JackpotLottery is ReentrancyGuard, IJackPotLottery, Ownable {
    using SafeERC20 for IERC20;

    address public operatorAddress;

    uint256 public currentLotteryId;

    uint256 public maxNumberTicketsPerRegisterOrClaim = 100;

    uint256 public constant MIN_LENGTH_LOTTERY = 4 hours - 5 minutes; // 4 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; // 4 days

    DVoucherNFT public dVoucher;
    IRandomNumberGenerator public randomGenerator;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    struct Lottery {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint8 class;    // 1-Bronze, 2-Silver, 3-Gold, 4-Platinum, 5-Mega
        uint256[6] rewardsBreakdown; // 0: 1 matching number // 5: 6 matching numbers
        uint256[6] rewardPerBracket;
        uint256[6] countWinnersPerBracket;
        uint256 totalReward;
        uint32 finalNumber;
    }

    struct Ticket {
        uint32 number;
        address owner;
    }

    mapping(uint256 => Lottery) private _lotteries; // lottery Id -> Lottery
    mapping(uint256 => Ticket[2]) private _tickets;    // dVoucher Id -> Ticket, 0 : Class, 1: Mega

    // Bracket calculator is used for verifying claims for ticket prizes
    mapping(uint32 => uint32) private _bracketCalculator;

    // Keeps track of number of ticket per unique combination for each lotteryId
    mapping(uint256 => mapping(uint32 => uint256)) private _numberTicketsPerLotteryId;

    // Keep track of user ticket ids for a given lotteryId
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerLotteryId;

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    event AdminTokenRecovery(address token, uint256 amount);
    event LotteryClose(uint256 indexed lotteryId);
    event LotteryOpen(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint8 class,
        uint256 totalReward
    );
    event LotteryNumberDrawn(uint256 indexed lotteryId, uint256 finalNumber, uint256 countWinningTickets);
    event NewOperatorAddress(address operatorAddress);
    event NewRandomGenerator(address indexed randomGenerator);
    event TicketsRegistered(address indexed sender, uint256 indexed lotteryId, uint256 numberTickets);
    event TicketsClaim(address indexed claimer, uint256 amount, uint256 indexed lotteryId, uint256 numberTickets);

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed prior to this contract
     * @param _dVoucherAddress: address of the DVoucher NFT
     * @param _randomGeneratorAddress: address of the RandomGenerator contract used to work with ChainLink VRF
     */
    constructor(address _dVoucherAddress, address _randomGeneratorAddress) {
        dVoucher = DVoucherNFT( _dVoucherAddress );
        randomGenerator = IRandomNumberGenerator( _randomGeneratorAddress );

        // Initializes a mapping
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
    }

    /**
     * @notice Register tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _dVoucherIds: dVoucher token Ids
     * @param _ticketNumbers: array of ticket numbers between 1,000,000 and 1,999,999
     * @dev Callable by users
     */
    function registerTickets(uint256 _lotteryId, uint256[] calldata _dVoucherIds, uint32[] calldata _ticketNumbers)
        external
        override
        notContract
        nonReentrant
    {
        require( _ticketNumbers.length != 0, "No ticket specified" );
        require( _ticketNumbers.length == _dVoucherIds.length, "Not same length" );
        require( _ticketNumbers.length <= maxNumberTicketsPerRegisterOrClaim, "Too many tickets" );

        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

        uint8 lotteryClass = _lotteries[_lotteryId].class;
        for ( uint256 i = 0; i < _dVoucherIds.length; i ++ ) {
            uint256 _dVoucherId = _dVoucherIds[i];
            require( dVoucher.ownerOf(_dVoucherId) == msg.sender, "Not owner of DVoucher" );
            
            uint8 nominal;
            bool partedInClass;
            bool partedInMega;
            if ( lotteryClass < 5 ) {
                (nominal, , partedInClass, partedInMega) = dVoucher.tokenInfo( _dVoucherId );
                require( lotteryClass == nominal, "Not correct class" );
                require( !partedInClass, "Already participated" );
            } else {
                require( !partedInMega, "Already participated" );
            }

            // dVoucher.transferFrom(msg.sender, address(this), _dVoucherId);
            if ( lotteryClass < 5 ) {
                dVoucher.setParticipateInfo(_dVoucherId, true, partedInMega);
            } else {
                dVoucher.setParticipateInfo(_dVoucherId, partedInClass, true);
            }

            uint32 thisTicketNumber = _ticketNumbers[i];
            require((thisTicketNumber >= 1000000) && (thisTicketNumber <= 1999999), "Outside range");

            _numberTicketsPerLotteryId[_lotteryId][1 + (thisTicketNumber % 10)]++;
            _numberTicketsPerLotteryId[_lotteryId][11 + (thisTicketNumber % 100)]++;
            _numberTicketsPerLotteryId[_lotteryId][111 + (thisTicketNumber % 1000)]++;
            _numberTicketsPerLotteryId[_lotteryId][1111 + (thisTicketNumber % 10000)]++;
            _numberTicketsPerLotteryId[_lotteryId][11111 + (thisTicketNumber % 100000)]++;
            _numberTicketsPerLotteryId[_lotteryId][111111 + (thisTicketNumber % 1000000)]++;

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(_dVoucherId);
            _tickets[_dVoucherId][lotteryClass / 5] = Ticket({number: thisTicketNumber, owner: msg.sender});
        }

        emit TicketsRegistered(msg.sender, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @param _ticketIds: array of DVoucher ids
     * @param _brackets: array of brackets for the ticket ids
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _brackets
    ) external override notContract nonReentrant {
        require(_ticketIds.length == _brackets.length, "Not same length");
        require(_ticketIds.length != 0, "Length must be >0");
        require(_ticketIds.length <= maxNumberTicketsPerRegisterOrClaim, "Too many tickets");
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");

        uint8 lotteryClass = _lotteries[_lotteryId].class;
        uint256 rewardToTransfer;
        for ( uint256 i = 0; i < _ticketIds.length; i ++ ) {
            require(_brackets[i] < 6, "Bracket out of range"); // Must be between 0 and 5

            uint256 thisTicketId = _ticketIds[i];
            require(msg.sender == _tickets[thisTicketId][lotteryClass / 5].owner, "Not the owner");
            
            // Update the lottery ticket owner to 0x address
            _tickets[thisTicketId][lotteryClass / 5].owner = address(0);

            uint256 rewardForTicketId = _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i]);

            // Check user is claiming the correct bracket
            require(rewardForTicketId != 0, "No prize for this bracket");

            if (_brackets[i] != 5) {
                require( _calculateRewardsForTicketId(_lotteryId, thisTicketId, _brackets[i] + 1) == 0, "Bracket must be higher" );
            }

            // Increment the reward to transfer
            rewardToTransfer += rewardForTicketId;
        }

        uint256 amount = rewardToTransfer / 1000;
        if (amount > 0) dVoucher.mint( msg.sender, 4, amount );
        amount = (rewardToTransfer % 1000) / 100;
        if (amount > 0) dVoucher.mint( msg.sender, 3, amount );
        amount = (rewardToTransfer % 100) / 10;
        if (amount > 0) dVoucher.mint( msg.sender, 2, amount );
        amount = rewardToTransfer % 10;
        if (amount > 0) dVoucher.mint( msg.sender, 1, amount );

        emit TicketsClaim(msg.sender, rewardToTransfer, _lotteryId, _ticketIds.length);
    }

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery( uint256 _lotteryId ) external override onlyOperator nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
        require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");

        // Request a random number from the generator based on a seed
        randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, block.timestamp))));

        _lotteries[_lotteryId].status = Status.Close;

        emit LotteryClose(_lotteryId);
    }

    /**
     * @notice Draw the final number, calculate reward per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(
        uint256 _lotteryId
    ) external override onlyOperator nonReentrant
    {
        require( _lotteries[_lotteryId].status == Status.Close, "Lottery not close") ;
        require( _lotteryId == randomGenerator.viewLatestLotteryId(), "Numbers not drawn" );

        // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
        uint32 finalNumber = randomGenerator.viewRandomResult();

        // Initialize a number to count addresses in the previous bracket
        uint256 numberAddressesInPreviousBracket;

        uint256 amountToWinners = _lotteries[_lotteryId].totalReward;

        // Calculate prizes for each bracket by starting from the highest one
        for (uint32 i = 0; i < 6; i++) {
            uint32 j = 5 - i;
            uint32 transformedWinningNumber = _bracketCalculator[j] + (finalNumber % (uint32(10)**(j + 1)));

            uint256 countWinners = _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber] - numberAddressesInPreviousBracket;
            _lotteries[_lotteryId].countWinnersPerBracket[j] = countWinners;

            // If number of users for this _bracket number is superior to 0
            if ( countWinners != 0 ) {
                // If rewards at this bracket are > 0, calculate, else, report the numberAddresses from previous bracket
                if (_lotteries[_lotteryId].rewardsBreakdown[j] != 0) {
                    _lotteries[_lotteryId].rewardPerBracket[j] = _lotteries[_lotteryId].rewardsBreakdown[j] * amountToWinners / countWinners / 10000;

                    // Update numberAddressesInPreviousBracket
                    numberAddressesInPreviousBracket = _numberTicketsPerLotteryId[_lotteryId][transformedWinningNumber];
                }
            } else {
                _lotteries[_lotteryId].rewardPerBracket[j] = 0;
            }
        }

        // Update internal statuses for lottery
        _lotteries[_lotteryId].finalNumber = finalNumber;
        _lotteries[_lotteryId].status = Status.Claimable;

        emit LotteryNumberDrawn(currentLotteryId, finalNumber, numberAddressesInPreviousBracket);
    }

    /**
     * @notice Change the random generator
     * @dev The calls to functions are used to verify the new generator implements them properly.
     * It is necessary to wait for the VRF response before starting a round.
     * Callable only by the contract owner
     * @param _randomGeneratorAddress: address of the random generator
     */
    function changeRandomGenerator(address _randomGeneratorAddress) external onlyOwner {
        require(_lotteries[currentLotteryId].status == Status.Claimable, "Lottery not in claimable");

        // Request a random number from the generator based on a seed
        IRandomNumberGenerator(_randomGeneratorAddress).getRandomNumber(
            uint256(keccak256(abi.encodePacked(currentLotteryId, block.timestamp)))
        );

        // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
        IRandomNumberGenerator(_randomGeneratorAddress).viewRandomResult();

        randomGenerator = IRandomNumberGenerator(_randomGeneratorAddress);

        emit NewRandomGenerator(_randomGeneratorAddress);
    }

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _rewardsBreakdown: breakdown of rewards per bracket (must sum to 10,000)
     * @param _class: lottery class (1-Bronze, 2-Silver, 3-Gold, 4-Platinum, 5-Mega)
     * @param _totalReward: total reward of this lottery
     */
    function startLottery(
        uint256 _endTime,
        uint256[6] calldata _rewardsBreakdown,
        uint8 _class,
        uint256 _totalReward
    ) external override onlyOperator {
        require(
            (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable),
            "Not time to start lottery"
        );

        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (_rewardsBreakdown[0] +
                _rewardsBreakdown[1] +
                _rewardsBreakdown[2] +
                _rewardsBreakdown[3] +
                _rewardsBreakdown[4] +
                _rewardsBreakdown[5]) == 10000,
            "Rewards must equal 10000"
        );

        require( _class > 0 && _class < 6, "Not right lottery class" );
        require( _totalReward > 0, "Must be > 0" );

        currentLotteryId++;

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            class: _class,
            rewardsBreakdown: _rewardsBreakdown,
            rewardPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)],
            countWinnersPerBracket: [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)],
            totalReward: _totalReward,
            finalNumber: 0
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _class,
            _totalReward
        );
    }

    /**
     * @notice It allows the admin to withdraw tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function withdrawTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
    }

    /**
     * @notice Set max number of tickets
     * @dev Only callable by owner
     */
    function setMaxNumberTicketsPerRegister(uint256 _maxNumberTicketsPerRegister) external onlyOwner {
        require(_maxNumberTicketsPerRegister != 0, "Must be > 0");
        maxNumberTicketsPerRegisterOrClaim = _maxNumberTicketsPerRegister;
    }

    /**
     * @notice Set operator, treasury, and injector addresses
     * @dev Only callable by owner
     * @param _operatorAddress: address of the operator
     */
    function setOperatorAddress( address _operatorAddress ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        
        operatorAddress = _operatorAddress;

        emit NewOperatorAddress(_operatorAddress);
    }

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() external view override returns (uint256) {
        return currentLotteryId;
    }

    /**
     * @notice View lottery information
     * @param _lotteryId: lottery id
     */
    function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
        return _lotteries[_lotteryId];
    }

    /**
     * @notice View ticker statuses and numbers for an array of ticket ids
     * @param _ticketIds: array of _ticketId
     * @param _isMegaLottery: is mega lottery or not
     */
    function viewNumbersAndStatusesForTicketIds(uint256[] calldata _ticketIds, bool _isMegaLottery)
        external
        view
        returns (uint32[] memory, bool[] memory)
    {
        uint8 index = _isMegaLottery ? 1 : 0;
        uint256 length = _ticketIds.length;
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            ticketNumbers[i] = _tickets[_ticketIds[i]][index].number;
            // True = isClaimed
            if (_tickets[_ticketIds[i]][index].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                ticketStatuses[i] = false;
            }
        }

        return (ticketNumbers, ticketStatuses);
    }

    /**
     * @notice View rewards for a given ticket, providing a bracket, and lottery id
     * @dev Computations are mostly offchain. This is used to verify a ticket!
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _bracket: bracket for the ticketId to verify the claim and calculate rewards
     */
    function viewRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket
    ) external view returns (uint256) {
        // Check lottery is in claimable status
        if (_lotteries[_lotteryId].status != Status.Claimable) {
            return 0;
        }

        return _calculateRewardsForTicketId(_lotteryId, _ticketId, _bracket);
    }

    /**
     * @notice View user ticket ids, numbers, and statuses of user for a given lottery
     * @param _user: user address
     * @param _lotteryId: lottery id
     * @param _cursor: cursor to start where to retrieve the tickets
     * @param _size: the number of tickets to retrieve
     */
    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        external
        view
        returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        )
    {
        uint256 length = _size;
        
        if (length > (_userTicketIdsPerLotteryId[_user][_lotteryId].length - _cursor)) {
            length = _userTicketIdsPerLotteryId[_user][_lotteryId].length - _cursor;
        }

        uint8 class = _lotteries[_lotteryId].class;
        uint256[] memory lotteryTicketIds = new uint256[](length);
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];
            ticketNumbers[i] = _tickets[lotteryTicketIds[i]][class / 5].number;

            // True = ticket claimed
            if (_tickets[lotteryTicketIds[i]][class / 5].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                // ticket not claimed (includes the ones that cannot be claimed)
                ticketStatuses[i] = false;
            }
        }

        return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
    }

    /**
     * @notice Calculate rewards for a given ticket
     * @param _lotteryId: lottery id
     * @param _ticketId: ticket id
     * @param _bracket: bracket for the ticketId to verify the claim and calculate rewards
     */
    function _calculateRewardsForTicketId(
        uint256 _lotteryId,
        uint256 _ticketId,
        uint32 _bracket
    ) internal view returns (uint256) {
        // Retrieve the winning number combination
        uint32 userNumber = _lotteries[_lotteryId].finalNumber;
        uint8 class = _lotteries[_lotteryId].class;

        // Retrieve the user number combination from the ticketId
        uint32 winningTicketNumber = _tickets[_ticketId][class / 5].number;

        // Apply transformation to verify the claim provided by the user is true
        uint32 transformedWinningNumber = _bracketCalculator[_bracket] +
            (winningTicketNumber % (uint32(10)**(_bracket + 1)));

        uint32 transformedUserNumber = _bracketCalculator[_bracket] + (userNumber % (uint32(10)**(_bracket + 1)));

        // Confirm that the two transformed numbers are the same, if not throw
        if (transformedWinningNumber == transformedUserNumber) {
            return _lotteries[_lotteryId].rewardPerBracket[_bracket];
        } else {
            return 0;
        }
    }

    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}