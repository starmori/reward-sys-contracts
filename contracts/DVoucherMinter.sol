// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./DVoucherNFT.sol";

contract DVoucherMinter is Ownable {
    DVoucherNFT public dVoucher;

    mapping( address => mapping( uint8 => uint256 ) ) public claimedAmount;

    event DVoucherClaimed(
        uint256 dVoucherAmount,
        address indexed userAddress,
        uint8 nonce
    );

    /**
     * @notice Constructor
     * @param _dVoucherAddress: address of the DVoucher NFT
     */
    constructor(address _dVoucherAddress) {
        dVoucher = DVoucherNFT( _dVoucherAddress );
    }

    function claim(
        uint256 _dVoucherAmount,
        address _userAddress,
        uint8 _nonce
    ) external {
        require( _dVoucherAmount > 0, "Must be > 0" );
        require( claimedAmount[_userAddress][_nonce] == 0, "Already Claimed" );

        claimedAmount[_userAddress][_nonce] = _dVoucherAmount;

        uint256 amount = _dVoucherAmount / 1000;
        if (amount > 0) dVoucher.mint( _userAddress, 4, amount );
        amount = (_dVoucherAmount % 1000) / 100;
        if (amount > 0) dVoucher.mint( _userAddress, 3, amount );
        amount = (_dVoucherAmount % 100) / 10;
        if (amount > 0) dVoucher.mint( _userAddress, 2, amount );
        amount = _dVoucherAmount % 10;
        if (amount > 0) dVoucher.mint( _userAddress, 1, amount );

        emit DVoucherClaimed(_dVoucherAmount, _userAddress, _nonce);
    }
}