// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DVoucherNFT is Context, AccessControlEnumerable, ERC721Enumerable, ERC721URIStorage {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdTracker;

    string private _baseTokenURI;
    string[4] public dVoucherTokenURIs;
    mapping ( uint256 => address ) public minter;

    mapping ( uint256 => uint8 ) private tokenNominals; // Map the nominal for each tokenId. Nominal : 1-Bronze, 2-Silver, 3-Gold, 4-Platinum
    mapping ( uint8 => string ) private nominalNames; // Map the name for each nominal
    mapping ( uint8 => uint256 ) public nominalCount; // Map the number of tokens per nominal
    mapping ( uint8 => uint256 ) public nominalBurnCount; // Map the number of tokens burnt per nominal

    // Modifier for admin roles
    modifier onlyOwner() {
        require( hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Not an admin role" );
        _;
    }

    constructor( string memory name, string memory symbol ) ERC721(name, symbol) {
        _baseTokenURI = "";
        _setupRole( DEFAULT_ADMIN_ROLE, _msgSender() );
    }

    function getNominal( uint256 _tokenId ) external view returns (uint8) {
        return tokenNominals[_tokenId];
    }

    function getNominalName( uint8 _nominal ) external view returns (string memory) {
        return nominalNames[_nominal];
    }

    function getNominalNameOfTokenId( uint256 _tokenId ) external view returns (string memory) {
        uint8 nominal = tokenNominals[_tokenId];
        return nominalNames[nominal];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI( string memory baseURI ) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setTokenURI( uint256 tokenId, string memory _tokenURI ) external onlyOwner {
        _setTokenURI( tokenId, _tokenURI );
    }

    function mint(
        address _to,
        uint8 _nominal,
        uint256 amount
    ) external onlyOwner {
        require( _nominal > 0 && _nominal < 5, "DVoucher : Nominal must be less than 5" );
        
        for(uint256 i = 0; i < amount; i ++) {
            uint256 newId = _tokenIdTracker.current();
            _tokenIdTracker.increment();

            tokenNominals[newId] = _nominal;
            nominalCount[_nominal] = nominalCount[_nominal] + 1;
            minter[newId] = msg.sender;

            _mint( _to, newId );
            _setTokenURI( newId, dVoucherTokenURIs[_nominal - 1] );
        }
    }

    function tokenMinter( uint256 tokenId ) public view returns ( address ) {
        return minter[tokenId];
    }

    function tokenURI( uint256 tokenId ) public view override( ERC721, ERC721URIStorage ) returns ( string memory ) {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function setDVoucherTokenURIs( string[4] calldata _dVoucherTokenURIs ) external onlyOwner {
        dVoucherTokenURIs[0] = _dVoucherTokenURIs[0];
        dVoucherTokenURIs[1] = _dVoucherTokenURIs[1];
        dVoucherTokenURIs[2] = _dVoucherTokenURIs[2];
        dVoucherTokenURIs[3] = _dVoucherTokenURIs[3];
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