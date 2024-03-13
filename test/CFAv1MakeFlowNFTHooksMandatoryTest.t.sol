// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import { ISuperfluid, ISuperToken, ISuperfluidGovernance, IConstantOutflowNFT, IConstantInflowNFT }
    from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { ConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/agreements/ConstantFlowAgreementV1.sol";
import { SuperfluidGovernanceII } from "@superfluid-finance/ethereum-contracts/contracts/gov/SuperfluidGovernanceII.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

using SuperTokenV1Library for ISuperToken;

contract SFAppTest is Test {
    ISuperfluid host;
    SuperfluidGovernanceII gov;

    function setUp() public {
        vm.createSelectFork("https://mainnet.optimism.io");
        address hostAddr = 0x567c4B141ED61923967cA25Ef4906C8781069a10;
        host = ISuperfluid(hostAddr);
        gov = SuperfluidGovernanceII(address(host.getGovernance()));
    }

    function _prepareAndVerifyScenario(ISuperToken superToken, address sender, address receiver) internal {
        console.log("deploying new CFA");
        ConstantFlowAgreementV1 newCFALogic = new ConstantFlowAgreementV1(host);
        address govOwner = gov.owner();
        vm.startPrank(govOwner);
        address[] memory newAgreementLogics = new address[](1);
        newAgreementLogics[0] = address(newCFALogic);
        console.log("updateContracts");
        gov.updateContracts({
            host: host,
            hostNewLogic: address(0),
            agreementClassNewLogics: newAgreementLogics,
            superTokenFactoryNewLogic: address(0),
            poolBeaconNewLogic: address(0)
        });
        vm.stopPrank();

        // verify that the flow exists and has no FlowNFT
        int96 curFr = superToken.getFlowRate(sender, receiver);
        console.log("curFr", uint96(curFr));
        assertGe(curFr, 2, "flowrate < 2");

        IConstantOutflowNFT cofNFT = IConstantOutflowNFT(superToken.CONSTANT_OUTFLOW_NFT());
        IConstantInflowNFT cifNFT = IConstantInflowNFT(superToken.CONSTANT_INFLOW_NFT());
        // the token id is the same for both COF and CIF NFTs
        uint256 flowNftTokenId = cofNFT.getTokenId(address(superToken), sender, receiver);
        vm.expectRevert();
        cofNFT.ownerOf(flowNftTokenId);

        vm.expectRevert();
        cifNFT.ownerOf(flowNftTokenId);
    }

    // test case: update the cfa contract, then update and then delete a specific flow
    function testUpdateDeleteFlowWithMissingNFT() public {

        // stream we use for testing
        // https://console.superfluid.finance/optimism-mainnet/streams/0x41bf11e307426c750b84a160891d09a2751cbaa5-0x6d18bbeca13387e3851877e433da1efeb77e0804-0x1828bff08bd244f7990eddcd9b19cc654b33cdb4-0.0
        ISuperToken superToken = ISuperToken(0x1828Bff08BD244F7990edDCd9B19cc654b33cDB4);
        address sender = 0x41BF11E307426c750B84A160891d09A2751CbAA5;
        address receiver = 0x6d18BBECA13387e3851877E433DA1eFEB77E0804;

        _prepareAndVerifyScenario(superToken, sender, receiver);

        // now we know for sure the flow exists and has no FlowNFTs. Go on with the actual test

        int96 newFr = 42;
        vm.startPrank(sender);
        superToken.updateFlow(receiver, newFr);
        superToken.deleteFlow(sender, receiver);
        vm.stopPrank();

        int96 curFr = superToken.getFlowRate(sender, receiver);
        console.log("curFr", uint96(curFr));
        assertEq(curFr, 0, "flowrate not 0");
    }
}
