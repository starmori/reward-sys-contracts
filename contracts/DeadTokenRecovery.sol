// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "./interfaces/IProtectedMarketplace.sol";
import "./interfaces/IDepository.sol";
import "./DVoucherNFT.sol";

contract DeadTokenRecovery is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    address public dumperShield;
    address private manager;

    IERC20 public USDT;
    DVoucherNFT public dVoucher;
    // IProtectedMarketplace public marketplace;
    IStaking public staking;

    enum OrderStatus { UnderDownsideProtectionPhase, Completed, Cancelled }
    
    struct Order {
        OrderStatus statusOrder;
        uint256 dVoucherAmount;
        address buyerAddress;
        // protection
        uint256 protectionAmount;
        uint256 protectionTime;
        //uint256 protectionExpiryTime = soldTime + protectionTime
        uint256 soldTime; // time when order sold, if equal to 0 than order unsold (so no need to use additional variable "bool saleNFT")
    }

    uint256 public orderIdCount;
    mapping(uint256 => Order) public orders;                     // identify offers by offerID

    mapping ( address => uint256 ) buyableDVoucher;

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    event DepositToken( address sender, address token, uint256 amount );
    event BuyDVoucher( uint256 orderId, address buyer, uint256 amount, uint256 protectionAmount, uint256 protectionExpiryTime );
    event ClaimDownsideProtectionByThis( uint256 orderId, uint256 statusOrder, uint256 soldTime, uint256 claimAmount );
    event ClaimDownsideProtectionByBuyer( uint256 orderId, uint256 statusOrder, uint256 soldTime, address buyer, uint256 claimAmount );

    constructor(
        address _dumperShield,
        address _usdtAddress,
        address _dVoucherAddress,
        address _staking,
        address _manager
    ) {
        dumperShield = _dumperShield;
        USDT = IERC20( _usdtAddress );
        dVoucher = DVoucherNFT( _dVoucherAddress );
        staking = IStaking( _staking );
        manager = _manager;
    }

    function depositToken( address _tokenAddress, uint256 _amount ) external notContract nonReentrant {
        require( IERC20(_tokenAddress).balanceOf(msg.sender) >= _amount, "Insufficient balance" );
        
        IERC20(_tokenAddress).safeTransferFrom(msg.sender, dumperShield, _amount);
        buyableDVoucher[msg.sender] += _amount / ERC20(_tokenAddress).decimals() / 100;

        emit DepositToken(msg.sender, _tokenAddress, _amount);
    }

    function buyDVoucher( uint256 _amount ) external notContract nonReentrant {
        require( buyableDVoucher[msg.sender] >= _amount, "Please deposit more token" );
        uint256 usdtAmount = _amount * tokenDecimal( address(USDT) );
        require( USDT.balanceOf(msg.sender) >= usdtAmount, "Insufficient USDT" );

        USDT.safeTransferFrom( msg.sender, address(this), usdtAmount );
        USDT.approve( address(staking), usdtAmount );
        staking.stake( usdtAmount, address(this) );
        
        buyableDVoucher[msg.sender] -= _amount;

        orderIdCount ++;
        Order storage order = orders[orderIdCount];

        // Update the order
        order.statusOrder = OrderStatus.UnderDownsideProtectionPhase;
        order.dVoucherAmount = _amount;
        order.buyerAddress = msg.sender;
        order.protectionAmount = usdtAmount;
        order.protectionTime = 365 * 3 days;
        order.soldTime = block.timestamp;

        uint256 amount = _amount / 1000;
        if (amount > 0) dVoucher.mint( msg.sender, 4, amount );
        amount = (_amount % 1000) / 100;
        if (amount > 0) dVoucher.mint( msg.sender, 3, amount );
        amount = (_amount % 100) / 10;
        if (amount > 0) dVoucher.mint( msg.sender, 2, amount );
        amount = _amount % 10;
        if (amount > 0) dVoucher.mint( msg.sender, 1, amount );

        emit BuyDVoucher(orderIdCount, msg.sender, _amount, usdtAmount, order.soldTime + order.protectionTime);
    }

    function claimDownsideProtectionAmount(uint256 _orderId, uint256[] calldata _tokenIds) external {
        Order storage order = orders[_orderId];
        require( order.statusOrder == OrderStatus.UnderDownsideProtectionPhase, "Invalid OrderStatus" );
        if ( block.timestamp > order.soldTime + order.protectionTime && order.soldTime != 0 ) { // when protection time expired
            require( _tokenIds.length == 0, "Not need this field" );
            
            order.statusOrder = OrderStatus.Completed;
            staking.claim( address(this) );
            staking.unstake( order.protectionAmount );
            USDT.safeTransfer( manager, USDT.balanceOf(address(this)) );

            emit ClaimDownsideProtectionByThis( _orderId, uint(order.statusOrder), order.soldTime, order.protectionAmount );
        } else if ( block.timestamp <= order.soldTime + order.protectionTime && order.soldTime != 0 ) { // claim by buyer
            require( msg.sender == order.buyerAddress, "Only buyer can claim" );
            require( _tokenIds.length > 0, "Must be > 0" );

            uint256 value = 0;
            for( uint256 i = 0; i < _tokenIds.length; i ++ ) {
                value += dVoucher.getNominal( _tokenIds[i] );
            }
            require( order.dVoucherAmount >= value, "No more than downside protection" );

            order.dVoucherAmount -= value;
            uint256 usdtAmount = value * tokenDecimal( address(USDT) );
            order.protectionAmount -= usdtAmount;
            if (order.dVoucherAmount == 0) {
                order.statusOrder = OrderStatus.Cancelled;
            }

            for( uint256 i = 0; i < _tokenIds.length; i ++ ) {
                require( msg.sender == dVoucher.ownerOf(_tokenIds[i]), "buyer is not NFT owner" );
                dVoucher.safeTransferFrom( msg.sender, address(0), _tokenIds[i] );
            }

            staking.claim( address(this) );
            staking.unstake( usdtAmount );
            USDT.safeTransfer( msg.sender, usdtAmount );
            USDT.safeTransfer( manager, USDT.balanceOf(address(this)) );

            emit ClaimDownsideProtectionByBuyer(_orderId, uint(order.statusOrder), order.soldTime, msg.sender, usdtAmount);
        }
    }

    function setManager( address _manager ) external onlyOwner {
        manager = _manager;
    }

    function tokenDecimal( address _token ) internal view returns (uint256) {
        return ERC20(_token).decimals();
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