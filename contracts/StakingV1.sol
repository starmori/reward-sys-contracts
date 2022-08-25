// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DVoucherNFT.sol";

contract StakingV1 is Ownable, ReentrancyGuard {
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastDepositTime;
    }

    IERC20 public tokenAddress;
    uint256 tokenPrice;
    uint256 lastRewardBlock;
    uint256 accTokenPerShare;
    uint256 balance;

    DVoucherNFT public dVoucher;
    uint256 public rewardPerBlock;  // in dVoucher price
    uint256 public constant BONUS_MULTIPLIER = 1;

    mapping( address => UserInfo ) public userInfo;
    uint256 public startBlock;
    uint256 public endBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claimed(address indexed user);

    constructor(
        address _dVoucherAddress,
        uint256 _startBlock,
        uint256 _rewardPerBlock,
        address _tokenAddress
    ) {
        dVoucher = DVoucherNFT( _dVoucherAddress );
        startBlock = _startBlock;
        rewardPerBlock = _rewardPerBlock;
        tokenAddress = IERC20( _tokenAddress );
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier( uint256 _from, uint256 _to ) public pure returns (uint256) {
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    function pendingReward( address _user ) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 myBlock = (block.number <= endBlock ) ? block.number : endBlock;
        uint256 accTokenPerShare_temp = accTokenPerShare;
        if ( myBlock > lastRewardBlock && balance != 0 ) {
            uint256 multiplier = getMultiplier( lastRewardBlock, myBlock );
            uint256 reward = multiplier * rewardPerBlock;
            accTokenPerShare_temp = accTokenPerShare_temp + reward * (1e12) / balance;
        }
        uint256 pending = user.amount * accTokenPerShare_temp / (1e12) - user.rewardDebt;
        return pending;
    }

    function updatePool() public {
        uint256 myBlock = (block.number <= endBlock ) ? block.number : endBlock;
        if ( myBlock <= lastRewardBlock ) {
            return;
        }
        if ( balance == 0 ) {
            lastRewardBlock = myBlock;
            return;
        }
        uint256 multiplier = getMultiplier( lastRewardBlock, myBlock );
        uint256 reward = multiplier * rewardPerBlock;
        accTokenPerShare = accTokenPerShare + reward * (1e12) / balance;
        lastRewardBlock = myBlock;
    }

    function deposit( uint256 _amount ) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        
        updatePool();
        payPendingToken();

        if ( _amount > 0 ) {
            uint256 oldBalance = tokenAddress.balanceOf( address(this) );
            tokenAddress.transferFrom( address(msg.sender), address(this), _amount );
            uint256 newBalance = tokenAddress.balanceOf( address(this) );
            
            _amount = newBalance - oldBalance;
            balance = balance + _amount;
            user.amount = user.amount + _amount;
            user.lastDepositTime = block.timestamp;
        }
        user.rewardDebt = user.amount * accTokenPerShare / (1e12);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw( uint256 _amount ) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require( user.amount >= _amount, "Withdraw : exceed amount" );

        updatePool();
        payPendingToken();

        if ( _amount > 0 ) {
            user.amount = user.amount - _amount;
            balance = balance - _amount;
            tokenAddress.transfer(msg.sender, _amount);
        }
        user.rewardDebt = user.amount * accTokenPerShare / (1e12);

        emit Withdraw(msg.sender, _amount);
    }

    function claim() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        updatePool();
        payPendingToken();

        user.rewardDebt = user.amount * accTokenPerShare / (1e12);

        emit Claimed(msg.sender);
    }

    function payPendingToken() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint256 pending = user.amount * accTokenPerShare / (1e12) - user.rewardDebt;

        if( pending > 0 ) {
            uint256 amount = pending / 1000;
            if (amount > 0) dVoucher.mint( msg.sender, 4, amount );
            amount = (pending % 1000) / 100;
            if (amount > 0) dVoucher.mint( msg.sender, 3, amount );
            amount = (pending % 100) / 10;
            if (amount > 0) dVoucher.mint( msg.sender, 2, amount );
            amount = pending % 10;
            if (amount > 0) dVoucher.mint( msg.sender, 1, amount );
        }
    }

    function setTokenPriceAndRewardPerBlock( uint256 _tokenPrice, uint256 _rewardPerBlock ) external onlyOwner {
        tokenPrice = _tokenPrice;
        rewardPerBlock = _rewardPerBlock;
    }
}