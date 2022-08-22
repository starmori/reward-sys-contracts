// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DVoucherNFT.sol";

contract TradingComp is Ownable {
    DVoucherNFT public immutable dVoucher;

    uint256 public competitionId;
    
    enum CompetitionStatus {
        Registration,
        Open,
        Close,
        Claiming,
        Over
    }
    CompetitionStatus public currentStatus;

    struct UserStats {
        bool hasRegistered; // true or false
        bool hasClaimed; // true or false
        uint256 ranking; // set 0 as default
        bool selfWinned; // true or false
        uint256 selfCompReward;
    }
    mapping( address => UserStats ) public userTradingStats;

    event RewardClaimed(address senderAddress, uint256 claimedReward);
    event NewCompetitionStatus(CompetitionStatus status, uint256 competitionId);
    event UserRegister(address userAddress, uint256 competitionId);
    event UserUpdateMultiple(address[] userAddresses, uint256[] ranking, bool[] selfWinned, uint256[] selfCompReward);

    constructor (
        address _dVoucherAddress,
        uint256 _competitionId
    ) {
        dVoucher = DVoucherNFT( _dVoucherAddress );
        competitionId = _competitionId;
        currentStatus = CompetitionStatus.Registration;
    }

    function claimReward() external {
        address senderAddress = _msgSender();
        UserStats memory userStats = userTradingStats[senderAddress];

        require( userStats.hasRegistered, "NOT_REGISTERED" );
        require( !userStats.hasClaimed, "HAS_CLAIMED" );
        require( currentStatus == CompetitionStatus.Claiming, "NOT_IN_CLAIMING" );
        require( userStats.ranking > 0 && userStats.ranking < 101, "NOT_CLAIMABLE_RANKING" );

        userTradingStats[senderAddress].hasClaimed = true;

        uint256 reward = (101 - userStats.ranking) * 100;
        if ( userStats.selfWinned ) {
            reward += userStats.selfCompReward;
        }
        uint256 amount = reward / 1000;
        if (amount > 0) dVoucher.mint( senderAddress, 4, amount );
        amount = (reward % 1000) / 100;
        if (amount > 0) dVoucher.mint( senderAddress, 3, amount );
        amount = (reward % 100) / 10;
        if (amount > 0) dVoucher.mint( senderAddress, 2, amount );
        amount = reward % 10;
        if (amount > 0) dVoucher.mint( senderAddress, 1, amount );

        emit RewardClaimed(senderAddress, reward);
    }

    function register() external {
        address senderAddress = _msgSender();

        require( !userTradingStats[senderAddress].hasRegistered, "HAS_REGISTERED" );
        require( currentStatus == CompetitionStatus.Registration, "NOT_IN_REGISTRATION" );

        UserStats storage newUserStats = userTradingStats[senderAddress];
        newUserStats.hasRegistered = true;

        emit UserRegister(senderAddress, competitionId);
    }

    function updateCompetitionStatus( CompetitionStatus _status ) external onlyOwner {
        require( _status != CompetitionStatus.Registration, "IN_REGISTRATION" );

        if ( _status == CompetitionStatus.Open ) {
            require( currentStatus == CompetitionStatus.Registration, "NOT_IN_REGISTRATION" );
        } else if ( _status == CompetitionStatus.Close ) {
            require( currentStatus == CompetitionStatus.Open, "NOT_OPEN" );
        } else if ( _status == CompetitionStatus.Claiming ) {
            require( currentStatus == CompetitionStatus.Close, "NOT_CLOSED" );
        } else {
            require( currentStatus == CompetitionStatus.Claiming, "NOT_CLAIMING" );
        }

        currentStatus = _status;

        emit NewCompetitionStatus(currentStatus, competitionId);
    }

    function updateUserStatusMultiple(
        address[] calldata _addressToUpdate,
        uint256[] calldata _ranking,
        bool[] calldata _selfWinned,
        uint256[] calldata _selfCompReward
    ) external onlyOwner {
        require(currentStatus == CompetitionStatus.Close, "NOT_CLOSED");
        uint256 length = _addressToUpdate.length;
        require(
            length == _ranking.length &&
            length == _selfWinned.length && 
            length == _selfCompReward.length,
            "LENGTH_NOT_MATCHED"
        );

        for( uint256 i = 0; i < length; i ++ ) {
            UserStats storage userStats = userTradingStats[_addressToUpdate[i]];
            require( userStats.hasRegistered, "NOT_REGISTERED" );
            require( !userStats.hasClaimed, "HAS_CLAIMED" );
            
            userStats.ranking = _ranking[i];
            userStats.selfWinned = _selfWinned[i];
            if(userStats.selfWinned) userStats.selfCompReward = _selfCompReward[i];
        }

        emit UserUpdateMultiple(_addressToUpdate, _ranking, _selfWinned, _selfCompReward);
    }

    function claimInformation( address _userAddress ) external view
    returns (bool, bool, uint256, bool, uint256) {
        UserStats memory userStats = userTradingStats[_userAddress];
        if ( (currentStatus != CompetitionStatus.Claiming) && (currentStatus != CompetitionStatus.Over) ) {
            return (userStats.hasRegistered, false, 0, false, 0);
        } else {
            return (
                userStats.hasRegistered, 
                userStats.hasClaimed,
                userStats.ranking,
                userStats.selfWinned,
                userStats.selfCompReward
            );
        }
    }
}