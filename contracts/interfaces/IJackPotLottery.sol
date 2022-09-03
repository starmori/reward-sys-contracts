// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IJackPotLottery {
    /**
     * @notice Buy tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _ticketNumbers: array of ticket numbers between 1,000,000 and 1,999,999
     * @dev Callable by users
     */
    function registerTickets(uint256 _lotteryId, uint256[] calldata _dVoucherIds, uint32[] calldata _ticketNumbers) external;

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @param _ticketIds: array of ticket ids
     * @param _brackets: array of brackets for the ticket ids
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketIds,
        uint32[] calldata _brackets
    ) external;

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(uint256 _lotteryId) external;

    /**
     * @notice Draw the final number, calculate reward in CAKE per group, and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawFinalNumberAndMakeLotteryClaimable(uint256 _lotteryId) external;

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
    ) external;

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() external returns (uint256);
}