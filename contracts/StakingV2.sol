// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DVoucherNFT.sol";

contract StakingV2 is Ownable, ReentrancyGuard {
    struct UserInfo {
        uint256 amount;
        uint256 startBlock;
    }

    IERC20 public tokenAddress;
    uint256 tokenPrice;

    DVoucherNFT public dVoucher;
    uint256 public rewardPerBlock;  // in dVoucher price
    uint256 public constant BONUS_MULTIPLIER = 1;

    mapping( address => UserInfo ) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claimed(address indexed user);

    constructor(
        address _dVoucherAddress,
        uint256 _rewardPerBlock,
        address _tokenAddress
    ) {
        dVoucher = DVoucherNFT( _dVoucherAddress );
        rewardPerBlock = _rewardPerBlock;
        tokenAddress = IERC20( _tokenAddress );
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier( uint256 _from, uint256 _to ) public pure returns (uint256) {
        return (_to - _from) * BONUS_MULTIPLIER;
    }

    function pendingReward( address _user ) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        
        if( user.amount == 0 ) return 0;
        uint256 multiplier = getMultiplier( user.startBlock, block.number );
        uint256 pending = user.amount * multiplier * rewardPerBlock;
        
        return pending;
    }

    function deposit( uint256 _amount ) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        
        payPendingToken();

        if ( _amount > 0 ) {
            uint256 oldBalance = tokenAddress.balanceOf( address(this) );
            tokenAddress.transferFrom( address(msg.sender), address(this), _amount );
            uint256 newBalance = tokenAddress.balanceOf( address(this) );
            
            _amount = newBalance - oldBalance;
            user.amount = user.amount + _amount;
            user.startBlock = block.timestamp;
        }

        emit Deposit(msg.sender, _amount);
    }

    function withdraw( uint256 _amount ) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require( user.amount >= _amount, "Withdraw : exceed amount" );

        payPendingToken();

        if ( _amount > 0 ) {
            user.amount = user.amount - _amount;
            tokenAddress.transfer(msg.sender, _amount);
        }

        emit Withdraw(msg.sender, _amount);
    }

    function claim() external nonReentrant {
        payPendingToken();

        emit Claimed(msg.sender);
    }

    function payPendingToken() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint256 multiplier = getMultiplier( user.startBlock, block.number );
        uint256 pending = user.amount * multiplier * rewardPerBlock;

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

    function setDVoucherAddress( address _dVoucherAddress ) external onlyOwner {
        dVoucher = DVoucherNFT( _dVoucherAddress );
    }

    function setTokenAddress( address _tokenAddress ) external onlyOwner {
        tokenAddress = IERC20( _tokenAddress );
    }
}