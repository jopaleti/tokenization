// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { ConfirmedOwner } from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    error dTSLA__NotEnoughCollateral();
    error dTSLA__DoesntMeetMinimumWithdrawalAmount();
    error dTSLA_TransferFailed();

    enum MinQrRedeem {
        mint,
        redeem
    }

    struct dTslaRequest {
        uint256 amountOfToken;
        address requester;
        MinQrRedeem mintQrRedeem;
    }
    // Math constant
    uint256 constant PRECISION = 1e18;

    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID = 0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;
    // OR
    // bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    address constant SEPOLIA_TSLA_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF; //This is link usd for demo purposes
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E; // USDC / USD address from chainlink
    address constant SEPOLIA_USDC = 0xAF0d217854155ea67D583E4CB5724f7caeC3Dc87;
    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;

    uint32 constant GAS_LIMIT = 300_000;
    uint256 constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    // If there is $200 of TSLA in the brokerage, we can mint AT MOST $100 of dTSLA
    uint256 constant COLLATERAL_PRECISION = 100;
    uint256 constant MINIMUM_WITHDRAW_AMOUNT = 100e18; // Because USDC has 6 decimals

    uint64 immutable i_subId;
    /*
        @title dTSLA
        @author Patrick Collins
     */
    /*//////////////////////////////////////////////////////////////
                                STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/
        string private s_mintSourceCode;
        string private s_redeemSourceCode;
        uint256 private s_portfolioBalance;
        mapping(bytes32 requestId => dTslaRequest request) private s_requestIdToRequest;
        mapping(address user => uint256 pendingWithdrawAmount) private s_userToWithdrawAmount;

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/
        constructor (string memory mintSourceCode, uint64 subId, string memory redeemSourceCode) ConfirmedOwner(msg.sender) FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER) ERC20("dTSLA", "dTSLA") {
            s_mintSourceCode = mintSourceCode;
            s_redeemSourceCode = redeemSourceCode;
            i_subId = subId;
        }
        // Send an HTTP request to:
        // 1. See how much TSLA is bought
        // 2. If enough TSLA is in the bank account, mint dTSLA
        // Two transaction functions
        function sendMintRequest(uint256 amount) external onlyOwner returns (bytes32) {
            FunctionsRequest.Request memory req;
            req.initializeRequestForInlineJavaScript(s_mintSourceCode);
            bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
            s_requestIdToRequest[requestId] = dTslaRequest(amount, msg.sender, MinQrRedeem.mint);
            return requestId;
        }

        // Return the amount of TSLA value (in usd) is stored in our broker
        // If we have enough TSLA token, mint dTSLA
        function _mintFufillRequest(bytes32 requestId, bytes memory response) internal {
            uint256 amountOfTokenToMint = s_requestIdToRequest[requestId].amountOfToken;
            s_portfolioBalance = uint256(bytes32(response));

            // If TSLA collateral (how much TSLA we've bought) > dTSLA to mint -> mint
            // How much TSLA in $$$ do we have?
            // How much TSLA in $$$ are we minting?
            if(_getCollateralRatioAdjustedTotalBalance(amountOfTokenToMint) > s_portfolioBalance) {
                revert dTSLA__NotEnoughCollateral();
            } 
            if (amountOfTokenToMint != 0) {
                _mint(s_requestIdToRequest[requestId].requester, amountOfTokenToMint);
            }
        }

        // @notice User sends a request to redeem dTSLA for USDC
        // This will have the chainlink function call our alpaca (bank) and do the following:
        // 1. Sell TSLA
        // 2. Buy USDC on the brokerage
        // 3. Send USDC to this contract for the user to withdraw
        function sendReedeemRequest(uint256 amountdTsla) external {
            uint256 amountTslaInUsdc = getUsdcValueOfUsd(getUsdValueOfTsla(amountdTsla));
            if (amountTslaInUsdc < MINIMUM_WITHDRAW_AMOUNT) {
                revert dTSLA__DoesntMeetMinimumWithdrawalAmount();
            }

            FunctionsRequest.Request memory req;
            req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

            string[] memory args = new string[](2);
            args[0] = amountdTsla.toString();
            args[1] = amountTslaInUsdc.toString();
            req.setArgs(args);

            bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
            s_requestIdToRequest[requestId] = dTslaRequest(amountdTsla, msg.sender, MinQrRedeem.redeem);

            _burn(msg.sender, amountdTsla);
        }

        function _redeemFufillRequest(bytes32 requestId, bytes memory response) internal {
            // Assume for now this has 18 decimals
            uint256 usdcAmount = uint256(bytes32(response));
            if (usdcAmount == 0) {
                uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfToken;
                _mint(s_requestIdToRequest[requestId].requester, amountOfdTSLABurned);
                return;
            }

            s_userToWithdrawAmount[s_requestIdToRequest[requestId].requester] += usdcAmount;
        }

        function withdraw() external {
            uint256 amountToWithdraw = s_userToWithdrawAmount[msg.sender];
            s_userToWithdrawAmount[msg.sender] = 0;

            bool success = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw);
            if (!success) {
                revert dTSLA_TransferFailed();
            }
        }

        function fulfillRequest(
            bytes32 requestId,
            bytes memory response,
            bytes memory /* err */
        ) internal override {
            if (s_requestIdToRequest[requestId].mintQrRedeem == MinQrRedeem.mint) {
                _mintFufillRequest(requestId, response);
            } else {
                _redeemFufillRequest(requestId, response);
            }
        }

        function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns(uint256) {
            uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
            return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
        }

        // The new expected total value in USD of all the dTSLA tokens combined
        function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal view returns (uint256) {
            return ((totalSupply() + addedNumberOfTokens) * getTslaPrice()) / PRECISION;
        }

        function getUsdcValueOfUsd(uint256 usdAmount) public view returns(uint256) {
            return (usdAmount * getUsdcPrice()) / PRECISION;
        }

        function getUsdValueOfTsla(uint256 tslaAmount) public view returns (uint256) {
            return (tslaAmount & getTslaPrice()) / PRECISION;
        }

        function getTslaPrice() public view returns(uint256) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEED);
            (, int256 price, , , ) = priceFeed.latestRoundData();
            return uint256(price) * ADDITIONAL_FEED_PRECISION;
        }

        function getUsdcPrice() public view returns (uint256) {
            AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
            (, int256 price, , , ) = priceFeed.latestRoundData();
            return uint256(price) * ADDITIONAL_FEED_PRECISION;
        }

        /*//////////////////////////////////////////////////////////////
                                VIEW AND PURE
        //////////////////////////////////////////////////////////////*/
        function getRequest(bytes32 requestId) public view returns(dTslaRequest memory) {
            return s_requestIdToRequest[requestId];
        }

        function getPendingWithdrawAmount(address user) public view returns (uint256) {
            return s_userToWithdrawAmount[user];
        }

        function getPortfolioBalance() public view returns (uint256) {
            return s_portfolioBalance;
        }

        function getSubId() public view returns (uint64) {
            return i_subId;
        }

        function getMinSourceCode() public view returns (string memory) {
            return s_mintSourceCode;
        }

        function getRedeemSourceCode() public view returns (string memory) {
            return s_redeemSourceCode;
        }

        function getCollateralRatio() public pure returns (uint256) {
            return COLLATERAL_RATIO;
        }

        function getCollateralPrecision() public pure returns (uint256) {
            return COLLATERAL_PRECISION;
        }
}