// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DVoucherNFT is Context, AccessControlEnumerable, ERC721Enumerable, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter public _tokenIdTracker;

    string private _baseTokenURI;
    address private _admin;
    mapping ( uint256 => address ) public minter;

    mapping ( uint256 => uint32 ) public tokenNominals; // 1-Bronze, 2-Silver, 3-Gold, 4-Platinum

    constructor( string memory name, string memory symbol ) ERC721(name, symbol) {
        _baseTokenURI = "";
        _admin = msg.sender;

        _setupRole( DEFAULT_ADMIN_ROLE, _admin );
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI( string memory baseURI ) external {
        require( hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "DVoucher : must have admin role to change base URI" );
        _baseTokenURI = baseURI;
    }

    function setTokenURI( uint256 tokenId, string memory _tokenURI ) external {
        require( hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "DVoucher : must have admin role to change token URI" );
        _setTokenURI( tokenId, _tokenURI );
    }

    function mint( uint32 nominal, uint256 amount ) external {
        require( hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "DVoucher : must have admin role to mint" );
        require( nominal > 0 && nominal < 5, "DVoucher : Nominal must be less than 5" );
        for( uint i = 0; i < amount; i ++ ) {
            _mint( msg.sender, _tokenIdTracker.current() );
            minter[_tokenIdTracker.current()] = msg.sender;
            tokenNominals[_tokenIdTracker.current()] = nominal;
            _tokenIdTracker.increment();
        }
    }

    function tokenMinter( uint256 tokenId ) public view returns ( address ) {
        return minter[tokenId];
    }

    function tokenURI( uint256 tokenId ) public view override( ERC721, ERC721URIStorage ) returns ( string memory ) {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function _beforeTokenTransfer( address from, address to, uint256 tokenId ) internal virtual override( ERC721, ERC721Enumerable ) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn( uint256 tokenId ) internal virtual override( ERC721, ERC721URIStorage ) {
        return ERC721URIStorage._burn(tokenId);
    }

    function supportsInterface( bytes4 interfaceId ) public view virtual override( AccessControlEnumerable, ERC721, ERC721Enumerable ) returns ( bool ) {
        return super.supportsInterface( interfaceId );
    }
}