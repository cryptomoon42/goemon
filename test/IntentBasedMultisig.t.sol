// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

import { IntentBasedMultisig } from "../src/IntentBasedMultisig.sol";

contract DummyCallee {
    bool public called;

    function call() external {
        called = true;
    }
}

contract IntentBasedMultisigTest is Test {
    IntentBasedMultisig internal multisig;
    address[] internal initialOwners;
    uint256 internal initialRequiredApprovals;
    DummyCallee internal dummyCallee;
    address internal dummyEthReceiver;

    function setUp() public virtual {
        initialOwners = [address(0x1), address(0x2), address(0x3)]; // 0x1, 0x2, 0x3 are dummy addresses
        initialRequiredApprovals = 2;
        multisig = new IntentBasedMultisig(initialOwners, initialRequiredApprovals);
        dummyCallee = new DummyCallee();
        dummyEthReceiver = makeAddr("dummyEthReceiver");
    }

    function test_setUp() public {
        assertEq(multisig.ownerCount(), initialOwners.length);
        assertEq(multisig.requiredApprovals(), initialRequiredApprovals);
        assertEq(multisig.nextIntentId(), 0);
        assertEq(multisig.isOwner(address(0x1)), true);
        assertEq(multisig.isOwner(address(0x2)), true);
        assertEq(multisig.isOwner(address(0x3)), true);
    }

    function test_ownerCanCreateIntent() public {
        vm.prank(initialOwners[0]);
        uint256 intentId = multisig.createIntent(address(dummyEthReceiver), 100, "");
        assertEq(intentId, 1);
        assertEq(multisig.nextIntentId(), 1);
        assertEq(multisig.hasApproved(1, initialOwners[0]), true);
    }

    function test_nonOwnerCannotCreateIntent() public {
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert("Not an owner");
        multisig.createIntent(address(dummyEthReceiver), 100, "");
    }

    function test_ownerCanApproveIntent() public {
        vm.prank(initialOwners[0]);
        multisig.createIntent(address(dummyEthReceiver), 100, "");
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);
        assertEq(multisig.hasApproved(1, initialOwners[0]), true);
        assertEq(multisig.hasApproved(1, initialOwners[1]), true);
        assertEq(multisig.hasApproved(1, initialOwners[2]), false);
    }

    function test_nonOwnerCannotApproveIntent() public {
        vm.prank(initialOwners[0]);
        multisig.createIntent(address(dummyEthReceiver), 100, "");
        vm.prank(makeAddr("nonOwner"));
        vm.expectRevert("Not an owner");
        multisig.approveIntent(1);
    }

    function test_intentCanBeExecutedAfterEnoughApprovals() public {
        deal(address(multisig), 100);
        vm.prank(initialOwners[0]);
        // intent to send 100 wei to dummyEthReceiver
        multisig.createIntent(address(dummyEthReceiver), 100, "");

        uint256 initialBalanceOfDummyEthReceiver = address(dummyEthReceiver).balance;
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);
        uint256 finalBalanceOfDummyEthReceiver = address(dummyEthReceiver).balance;
        // dummyEthReceiver received 100 wei
        assertEq(finalBalanceOfDummyEthReceiver, initialBalanceOfDummyEthReceiver + 100);
        assertEq(address(multisig).balance, 0);

        (,,,, bool executed) = multisig.intents(1);
        assertEq(executed, true);
    }

    function test_intentCannotBeExecutedIfNotEnoughApprovals() public {
        vm.prank(initialOwners[0]);
        multisig.createIntent(address(dummyEthReceiver), 100, "");
        vm.prank(initialOwners[1]);
        vm.expectRevert("Not enough approvals");
        multisig.executeIntent(1);
    }

    function test_successfullyExecuteContractCallIntentAfterEnoughApprovals() public {
        vm.prank(initialOwners[0]);
        multisig.createIntent(address(dummyCallee), 0, abi.encodeWithSelector(DummyCallee.call.selector));
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);
        (,,,, bool executed) = multisig.intents(1);
        assertEq(executed, true);
        assertEq(dummyCallee.called(), true);
    }

    function test_updateRequiredApprovalsRevertWithoutIntent() public {
        vm.prank(initialOwners[0]);
        vm.expectRevert("Only callable by contract");
        multisig.updateRequiredApprovals(3);
    }

    function test_updateRequiredApprovalsSuccessWithIntentAndEnoughApprovals() public {
        vm.prank(initialOwners[0]);
        // intent to update the required approvals to 1
        // previous required approvals is 2
        multisig.createIntent(
            address(multisig), 0, abi.encodeWithSelector(IntentBasedMultisig.updateRequiredApprovals.selector, 1)
        );
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);
        (,,,, bool executed) = multisig.intents(1);

        assertEq(executed, true);
        assertEq(multisig.requiredApprovals(), 1);

        vm.prank(initialOwners[0]);
        multisig.createIntent(address(dummyCallee), 0, abi.encodeWithSelector(DummyCallee.call.selector));
        (,,,, executed) = multisig.intents(2);
        assertEq(executed, true);
        assertEq(dummyCallee.called(), true);
    }

    function test_removeOwnerCallRevertWithoutIntent() public {
        vm.prank(initialOwners[0]);
        vm.expectRevert("Only callable by contract");
        multisig.removeOwner(initialOwners[1]);
    }

    function test_removeOwnerSuccessWithIntentAndEnoughApprovals() public {
        vm.prank(initialOwners[0]);
        // intent to remove owner 0x1
        multisig.createIntent(
            address(multisig), 0, abi.encodeWithSelector(IntentBasedMultisig.removeOwner.selector, initialOwners[1])
        );
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);
        (,,,, bool executed) = multisig.intents(1);
        assertEq(executed, true);
        assertEq(multisig.isOwner(initialOwners[1]), false);
        assertEq(multisig.ownerCount(), 2);
    }

    function test_addOwnerCallRevertWithoutIntent() public {
        vm.prank(initialOwners[0]);
        vm.expectRevert("Only callable by contract");
        multisig.addOwner(initialOwners[1]);
    }

    function test_addOwnerSuccessWithIntentAndEnoughApprovals() public {
        vm.prank(initialOwners[0]);
        // intent to add owner 0x4
        multisig.createIntent(
            address(multisig), 0, abi.encodeWithSelector(IntentBasedMultisig.addOwner.selector, address(0x4))
        );
        vm.prank(initialOwners[1]);
        multisig.approveIntent(1);

        (,,,, bool executed) = multisig.intents(1);
        assertEq(executed, true);
        // address 0x4 is an owner
        assertEq(multisig.isOwner(address(0x4)), true);
        // owner count is 4
        assertEq(multisig.ownerCount(), 4);
    }
}
