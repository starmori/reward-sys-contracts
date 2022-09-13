// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDepository {
    function deposit() external payable returns ( uint256 );
    function withdraw( uint256 depositId ) external returns ( uint256 );
}

interface IStaking {
    function stake( uint _amount, address _recipient ) external returns ( bool );
    function claim ( address _recipient ) external;
    function unstake( uint _amount ) external;
}