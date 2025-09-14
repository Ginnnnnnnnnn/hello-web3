// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {LibTransferSafeUpgradeable, IERC721} from "./libraries/LibTransferSafeUpgradeable.sol";
import {Price} from "./libraries/RedBlackTreeLibrary.sol";
import {LibOrder, OrderKey} from "./libraries/LibOrder.sol";
import {LibPayInfo} from "./libraries/LibPayInfo.sol";

import {IEasySwapOrderBook} from "./interface/IEasySwapOrderBook.sol";
import {IEasySwapVault} from "./interface/IEasySwapVault.sol";

import {OrderStorage} from "./OrderStorage.sol";
import {OrderValidator} from "./OrderValidator.sol";
import {ProtocolManager} from "./ProtocolManager.sol";

// 订单簿合约
// IEasySwapOrderBook 订单簿合约-接口
// Initializable 可升级合约
// ContextUpgradeable 可升级合约-上下文
// OwnableUpgradeable 可升级合约-owner
// ReentrancyGuardUpgradeable 防重入攻击合约
// PausableUpgradeable 紧急暂停合约
// OrderStorage 订单存储合约
// ProtocolManager 协议费管理合约
// OrderValidator 资产管理合约
contract EasySwapOrderBook is
    IEasySwapOrderBook,
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    OrderStorage,
    ProtocolManager,
    OrderValidator
{
    using LibTransferSafeUpgradeable for address;
    using LibTransferSafeUpgradeable for IERC721;

    event LogMake(
        OrderKey orderKey,
        LibOrder.Side indexed side,
        LibOrder.SaleKind indexed saleKind,
        address indexed maker,
        LibOrder.Asset nft,
        Price price,
        uint64 expiry,
        uint64 salt
    );

    event LogCancel(OrderKey indexed orderKey, address indexed maker);

    event LogMatch(
        OrderKey indexed makeOrderKey,
        OrderKey indexed takeOrderKey,
        LibOrder.Order makeOrder,
        LibOrder.Order takeOrder,
        uint128 fillPrice
    );

    event LogWithdrawETH(address recipient, uint256 amount);
    event BatchMatchInnerError(uint256 offset, bytes msg);
    event LogSkipOrder(OrderKey orderKey, uint64 salt);

    modifier onlyDelegateCall() {
        _checkDelegateCall();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable self = address(this);

    // 资产管理合约地址
    address private _vault;

    //============================== 初始化方法 ==============================

    /**
     * @notice Initialize contracts.
     * @param newProtocolShare 默认协议费
     * @param newVault 资产管理合约地址
     */
    function initialize(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) public initializer {
        __EasySwapOrderBook_init(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __EasySwapOrderBook_init_unchained(
            newProtocolShare,
            newVault,
            EIP712Name,
            EIP712Version
        );
    }

    function __EasySwapOrderBook_init_unchained(
        uint128 newProtocolShare,
        address newVault,
        string memory EIP712Name,
        string memory EIP712Version
    ) internal onlyInitializing {
        __Context_init();
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();

        __OrderStorage_init();
        __ProtocolManager_init(newProtocolShare);
        __OrderValidator_init(EIP712Name, EIP712Version);

        setVault(newVault);
    }

    /**
     * @notice 创建订单-批量
     * @dev 挂单：您需要首先授权EasySwapVault合约。
     * @dev 买单：创建出价订单将把ETH转移到订单池。
     * @dev order.maker必须是msg.sender。
     * @dev order.price不能为0。
     * @dev order.expiry 必须大于当前区块时间。
     * @dev order.salt 不能为0。
     * @param newOrders 订单信息数组
     * @return newOrderKeys 订单ID按顺序返回，如果ID为空，则相应的订单未正确创建。
     */
    function makeOrders(
        LibOrder.Order[] calldata newOrders
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory newOrderKeys)
    {
        uint256 orderAmount = newOrders.length;
        // 订单ID
        newOrderKeys = new OrderKey[](orderAmount);
        // 成功金额
        uint128 ETHAmount;
        // 遍历参数
        for (uint256 i = 0; i < orderAmount; ++i) {
            // 判断是否是买单，计算购买总价格。单价 * 数量
            uint128 buyPrice;
            if (newOrders[i].side == LibOrder.Side.Bid) {
                buyPrice =
                    Price.unwrap(newOrders[i].price) *
                    newOrders[i].nft.amount;
            }
            // 创建订单
            OrderKey newOrderKey = _makeOrderTry(newOrders[i], buyPrice);
            newOrderKeys[i] = newOrderKey;
            // 记录创建成功金额
            if (
                OrderKey.unwrap(newOrderKey) !=
                OrderKey.unwrap(LibOrder.ORDERKEY_SENTINEL)
            ) {
                ETHAmount += buyPrice;
            }
        }
        // 如果用户支付金额 > 成功金额，退还剩余ETH
        if (msg.value > ETHAmount) {
            _msgSender().safeTransferETH(msg.value - ETHAmount);
        }
    }

    /**
     * @dev 取消订单-批量
     * @param orderKeys 订单ID数组
     */
    function cancelOrders(
        OrderKey[] calldata orderKeys
    )
        external
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory successes)
    {
        successes = new bool[](orderKeys.length);
        // 遍历参数
        for (uint256 i = 0; i < orderKeys.length; ++i) {
            // 取消订单
            bool success = _cancelOrderTry(orderKeys[i]);
            successes[i] = success;
        }
    }

    /**
     * @notice 编辑订单-批量
     * @dev newOrder的saleKind、side、maker和nft必须与oldOrderKey的对应顺序匹配，否则将被跳过；只有价格可以修改。
     * @dev newOrder的有效期和盐可以再生。
     * @param editDetails 订单信息
     * @return newOrderKeys 订单ID按顺序返回，如果ID为空，则相应的订单未被正确编辑。
     */
    function editOrders(
        LibOrder.EditDetail[] calldata editDetails
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (OrderKey[] memory newOrderKeys)
    {
        newOrderKeys = new OrderKey[](editDetails.length);
        // 成功金额
        uint256 bidETHAmount;
        // 遍历参数
        for (uint256 i = 0; i < editDetails.length; ++i) {
            // 遍历金额
            (OrderKey newOrderKey, uint256 bidPrice) = _editOrderTry(
                editDetails[i].oldOrderKey,
                editDetails[i].newOrder
            );
            bidETHAmount += bidPrice;
            newOrderKeys[i] = newOrderKey;
        }
        // 如果用户支付金额 > 成功金额，退还剩余ETH
        if (msg.value > bidETHAmount) {
            _msgSender().safeTransferETH(msg.value - bidETHAmount);
        }
    }

    /**
     * @dev 匹配订单
     * @param sellOrder 买单信息
     * @param buyOrder 买单信息
     */
    function matchOrder(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder
    ) external payable override whenNotPaused nonReentrant {
        // 匹配订单
        uint256 costValue = _matchOrder(sellOrder, buyOrder, msg.value);
        // 如果用户支付金额 > 成功金额，退还剩余ETH
        if (msg.value > costValue) {
            _msgSender().safeTransferETH(msg.value - costValue);
        }
    }

    /**
     * @dev 匹配订单-批量
     * @dev 买单，使用 买单 和 挂单 进行匹配：
     * @dev    buyOrder.side = Bid，buyOrder.saleKind = FixedPriceForItem，buyOrder.maker = msg.sender，
     * @dev    买单价值 与 NFT价值 相等，buyOrder.expiry > block.timestamp, buyOrder.salt != 0;
     * @dev 挂单，使用 挂单 和 买单 进行匹配：
     * @dev    sellOrder.side = List，sellOrder.saleKind = FixedPriceForItem，sellOrder.maker = msg.sender，
     * @dev    NFT价值 与 买单价值 相等，sellOrder.expiry > block.timestamp、sellOrder.salt != 0;
     * @param matchDetails 包含要匹配的卖出和买入订单详细信息的 MatchDetail 结构体数组。
     */
    function matchOrders(
        LibOrder.MatchDetail[] calldata matchDetails
    )
        external
        payable
        override
        whenNotPaused
        nonReentrant
        returns (bool[] memory successes)
    {
        successes = new bool[](matchDetails.length);
        // 成功金额
        uint128 buyETHAmount;
        // 遍历参数
        for (uint256 i = 0; i < matchDetails.length; ++i) {
            // 匹配订单，这种调用防止整体回滚，只会回滚单笔
            LibOrder.MatchDetail calldata matchDetail = matchDetails[i];
            (bool success, bytes memory data) = address(this).delegatecall(
                abi.encodeWithSignature(
                    "matchOrderWithoutPayback((uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),(uint8,uint8,address,(uint256,address,uint96),uint128,uint64,uint64),uint256)",
                    matchDetail.sellOrder,
                    matchDetail.buyOrder,
                    msg.value - buyETHAmount
                )
            );
            // 判断是否匹配成功
            if (success) {
                // 设置
                successes[i] = success;
                if (matchDetail.buyOrder.maker == _msgSender()) {
                    // 累计成功金额
                    uint128 buyPrice;
                    buyPrice = abi.decode(data, (uint128));
                    buyETHAmount += buyPrice;
                }
            } else {
                // 发送匹配失败事件
                emit BatchMatchInnerError(i, data);
            }
        }
        // 如果用户支付金额 > 成功金额，退还剩余ETH
        if (msg.value > buyETHAmount) {
            _msgSender().safeTransferETH(msg.value - buyETHAmount);
        }
    }

    /**
     * @dev 匹配订单-不回滚
     * @param sellOrder 挂单
     * @param buyOrder 买单
     * @param msgValue 交易金额
     */
    function matchOrderWithoutPayback(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        uint256 msgValue
    )
        external
        payable
        whenNotPaused
        onlyDelegateCall
        returns (uint128 costValue)
    {
        costValue = _matchOrder(sellOrder, buyOrder, msgValue);
    }

    /**
     * @dev 创建订单
     * @param order 订单信息
     * @param ETHAmount 支付ETH金额
     * @return newOrderKey 订单ID
     */
    function _makeOrderTry(
        LibOrder.Order calldata order,
        uint128 ETHAmount
    ) internal returns (OrderKey newOrderKey) {
        if (
            order.maker == _msgSender() && // 下单必须是拥有者
            Price.unwrap(order.price) != 0 && // 价格必须大于0
            order.salt != 0 && // 盐必须大于0
            (order.expiry > block.timestamp || order.expiry == 0) && // 过期时间不能是0并且必须大于当前区块时间
            filledAmount[LibOrder.hash(order)] == 0 // 状态校验
        ) {
            // 生成订单ID
            newOrderKey = LibOrder.hash(order);
            // 判断挂单还是买单
            if (order.side == LibOrder.Side.List) {
                if (order.nft.amount != 1) {
                    // 限制NFT数量必须是1
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                // 存入NFT
                IEasySwapVault(_vault).depositNFT(
                    newOrderKey,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            } else if (order.side == LibOrder.Side.Bid) {
                // 限制NFT数量必须是0
                if (order.nft.amount == 0) {
                    return LibOrder.ORDERKEY_SENTINEL;
                }
                // 存入ETH
                IEasySwapVault(_vault).depositETH{value: uint256(ETHAmount)}(
                    newOrderKey,
                    ETHAmount
                );
            }
            // 存入订单信息
            _addOrder(order);
            // 发送事件
            emit LogMake(
                newOrderKey,
                order.side,
                order.saleKind,
                order.maker,
                order.nft,
                order.price,
                order.expiry,
                order.salt
            );
        } else {
            // 发送事件
            emit LogSkipOrder(LibOrder.hash(order), order.salt);
        }
    }

    /**
     * @dev 取消订单
     * @param orderKey 取消订单
     */
    function _cancelOrderTry(
        OrderKey orderKey
    ) internal returns (bool success) {
        // 获取订单信息
        LibOrder.Order memory order = orders[orderKey].order;
        // 校验参数
        if (
            order.maker == _msgSender() &&
            filledAmount[orderKey] < order.nft.amount // 只有未完成的订单才能取消
        ) {
            OrderKey orderHash = LibOrder.hash(order);
            // 删除订单
            _removeOrder(order);
            // 判断挂单还是买单
            if (order.side == LibOrder.Side.List) {
                // 退回NFT
                IEasySwapVault(_vault).withdrawNFT(
                    orderHash,
                    order.maker,
                    order.nft.collection,
                    order.nft.tokenId
                );
            } else if (order.side == LibOrder.Side.Bid) {
                // 减掉已经匹配成功数量
                uint256 availNFTAmount = order.nft.amount -
                    filledAmount[orderKey];
                // 退回ETH
                IEasySwapVault(_vault).withdrawETH(
                    orderHash,
                    Price.unwrap(order.price) * availNFTAmount,
                    order.maker
                );
            }
            // 更改订单状态为取消
            _cancelOrder(orderKey);
            success = true;
            emit LogCancel(orderKey, order.maker);
        } else {
            emit LogSkipOrder(orderKey, order.salt);
        }
    }

    /**
     * @notice 编辑订单
     * @param oldOrderKey 订单ID
     * @param newOrder 新订单信息
     * @return newOrderKey 新订单ID
     * @return deltaBidPrice 订单总金额
     */
    function _editOrderTry(
        OrderKey oldOrderKey,
        LibOrder.Order calldata newOrder
    ) internal returns (OrderKey newOrderKey, uint256 deltaBidPrice) {
        LibOrder.Order memory oldOrder = orders[oldOrderKey].order;
        // 检查订单，只能修改价格和金额
        if (
            (oldOrder.saleKind != newOrder.saleKind) ||
            (oldOrder.side != newOrder.side) ||
            (oldOrder.maker != newOrder.maker) ||
            (oldOrder.nft.collection != newOrder.nft.collection) ||
            (oldOrder.nft.tokenId != newOrder.nft.tokenId) ||
            filledAmount[oldOrderKey] >= oldOrder.nft.amount // 判断订单完成状态
        ) {
            emit LogSkipOrder(oldOrderKey, oldOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        // 检查新订单是否有效
        if (
            newOrder.maker != _msgSender() ||
            newOrder.salt == 0 ||
            (newOrder.expiry < block.timestamp && newOrder.expiry != 0) ||
            filledAmount[LibOrder.hash(newOrder)] != 0 // order cannot be canceled or filled
        ) {
            emit LogSkipOrder(oldOrderKey, newOrder.salt);
            return (LibOrder.ORDERKEY_SENTINEL, 0);
        }
        // 取消旧订单
        _removeOrder(oldOrder); // 从订单存储中删除订单
        _cancelOrder(oldOrderKey); // 从订单簿中取消订单
        emit LogCancel(oldOrderKey, oldOrder.maker);
        // 添加新订单
        newOrderKey = _addOrder(newOrder);
        // 处理资产
        uint256 oldFilledAmount = filledAmount[oldOrderKey];
        if (oldOrder.side == LibOrder.Side.List) {
            // 存入NFT
            IEasySwapVault(_vault).editNFT(oldOrderKey, newOrderKey);
        } else if (oldOrder.side == LibOrder.Side.Bid) {
            // 旧订单金额剩余金额。（旧订单NFT数量 - 已成交NFT数量） * 旧订单单价
            uint256 oldRemainingPrice = Price.unwrap(oldOrder.price) *
                (oldOrder.nft.amount - oldFilledAmount);
            // 新订单金额
            uint256 newRemainingPrice = Price.unwrap(newOrder.price) *
                newOrder.nft.amount;
            // 判断 新订单金额 是否大于 旧订单剩余金额
            if (newRemainingPrice > oldRemainingPrice) {
                // 新订单金额 - 旧订单剩余金额
                deltaBidPrice = newRemainingPrice - oldRemainingPrice;
                // 存入ETH
                IEasySwapVault(_vault).editETH{value: uint256(deltaBidPrice)}(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker
                );
            } else {
                // 存入ETH
                IEasySwapVault(_vault).editETH(
                    oldOrderKey,
                    newOrderKey,
                    oldRemainingPrice,
                    newRemainingPrice,
                    oldOrder.maker
                );
            }
        }
        // 发送事件
        emit LogMake(
            newOrderKey,
            newOrder.side,
            newOrder.saleKind,
            newOrder.maker,
            newOrder.nft,
            newOrder.price,
            newOrder.expiry,
            newOrder.salt
        );
    }

    /**
     * @dev 匹配订单-内部方法
     * @param sellOrder 挂单
     * @param buyOrder 买单
     * @param msgValue 交易金额
     */
    function _matchOrder(
        LibOrder.Order calldata sellOrder,
        LibOrder.Order calldata buyOrder,
        uint256 msgValue
    ) internal returns (uint128 costValue) {
        // 挂单信息
        OrderKey sellOrderKey = LibOrder.hash(sellOrder);
        // 买单信息
        OrderKey buyOrderKey = LibOrder.hash(buyOrder);
        // 校验匹配
        _isMatchAvailable(sellOrder, buyOrder, sellOrderKey, buyOrderKey);
        // 判断发起方是 挂单方 还是 买单方
        if (_msgSender() == sellOrder.maker) {
            // 参数校验
            require(msgValue == 0, "HD: value > 0");
            bool isSellExist = orders[sellOrderKey].order.maker != address(0);
            _validateOrder(sellOrder, isSellExist);
            _validateOrder(orders[buyOrderKey].order, false);
            // 处理订单数据
            if (isSellExist) {
                // 删除订单
                _removeOrder(sellOrder);
                // 更新完成数量
                _updateFilledAmount(sellOrder.nft.amount, sellOrderKey);
            }
            _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);
            // 买单出价
            uint128 fillPrice = Price.unwrap(buyOrder.price);
            // 发送匹配事件
            emit LogMatch(
                sellOrderKey,
                buyOrderKey,
                sellOrder,
                buyOrder,
                fillPrice
            );
            // 取出ETH
            IEasySwapVault(_vault).withdrawETH(
                buyOrderKey,
                fillPrice,
                address(this)
            );
            // 交易手续费
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            // 转账扣除交易手续费后的ETH给挂单方
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            // 处理NFT
            if (isSellExist) {
                // 转账NFT给买家
                IEasySwapVault(_vault).withdrawNFT(
                    sellOrderKey,
                    buyOrder.maker,
                    sellOrder.nft.collection,
                    sellOrder.nft.tokenId
                );
            } else {
                // 订单不存在从用户转移到买家
                IEasySwapVault(_vault).transferERC721(
                    sellOrder.maker,
                    buyOrder.maker,
                    sellOrder.nft
                );
            }
        } else if (_msgSender() == buyOrder.maker) {
            // 参数校验
            bool isBuyExist = orders[buyOrderKey].order.maker != address(0);
            _validateOrder(orders[sellOrderKey].order, false);
            _validateOrder(buyOrder, isBuyExist);
            // 买单出价
            uint128 buyPrice = Price.unwrap(buyOrder.price);
            // 卖单报价
            uint128 fillPrice = Price.unwrap(sellOrder.price);
            if (!isBuyExist) {
                // 订单存在-校验价格
                require(msgValue >= fillPrice, "HD: value < fill price");
            } else {
                // 订单不存在-校验价格
                require(buyPrice >= fillPrice, "HD: buy price < fill price");
                // 取出ETH
                IEasySwapVault(_vault).withdrawETH(
                    buyOrderKey,
                    buyPrice,
                    address(this)
                );
                // 删除订单
                _removeOrder(buyOrder);
                // 更新完成数量
                _updateFilledAmount(filledAmount[buyOrderKey] + 1, buyOrderKey);
            }
            _updateFilledAmount(sellOrder.nft.amount, sellOrderKey);
            // 发送匹配事件
            emit LogMatch(
                buyOrderKey,
                sellOrderKey,
                buyOrder,
                sellOrder,
                fillPrice
            );
            // 交易手续费
            uint128 protocolFee = _shareToAmount(fillPrice, protocolShare);
            // 转账扣除交易手续费后的ETH给卖家
            sellOrder.maker.safeTransferETH(fillPrice - protocolFee);
            if (buyPrice > fillPrice) {
                // 剩余金额退还给买家
                buyOrder.maker.safeTransferETH(buyPrice - fillPrice);
            }
            // 转账NFT给买家
            IEasySwapVault(_vault).withdrawNFT(
                sellOrderKey,
                buyOrder.maker,
                sellOrder.nft.collection,
                sellOrder.nft.tokenId
            );
            // 记录订单不存在时，成功金额
            costValue = isBuyExist ? 0 : buyPrice;
        } else {
            revert("HD: sender invalid");
        }
    }

    /**
     * @dev 匹配校验
     * @param sellOrder 挂单信息
     * @param buyOrder 买单信息
     * @param sellOrderKey 挂单ID
     * @param buyOrderKey 买单ID
     */
    function _isMatchAvailable(
        LibOrder.Order memory sellOrder,
        LibOrder.Order memory buyOrder,
        OrderKey sellOrderKey,
        OrderKey buyOrderKey
    ) internal view {
        require(
            OrderKey.unwrap(sellOrderKey) != OrderKey.unwrap(buyOrderKey),
            "HD: same order"
        );
        require(
            sellOrder.side == LibOrder.Side.List &&
                buyOrder.side == LibOrder.Side.Bid,
            "HD: side mismatch"
        );
        require(
            sellOrder.saleKind == LibOrder.SaleKind.FixedPriceForItem,
            "HD: kind mismatch"
        );
        require(sellOrder.maker != buyOrder.maker, "HD: same maker");
        require( // check if the asset is the same
            buyOrder.saleKind == LibOrder.SaleKind.FixedPriceForCollection ||
                (sellOrder.nft.collection == buyOrder.nft.collection &&
                    sellOrder.nft.tokenId == buyOrder.nft.tokenId),
            "HD: asset mismatch"
        );
        require(
            filledAmount[sellOrderKey] < sellOrder.nft.amount &&
                filledAmount[buyOrderKey] < buyOrder.nft.amount,
            "HD: order closed"
        );
    }

    /**
     * @notice caculate amount based on share.
     * @param total the total amount.
     * @param share the share in base point.
     */
    function _shareToAmount(
        uint128 total,
        uint128 share
    ) internal pure returns (uint128) {
        return (total * share) / LibPayInfo.TOTAL_SHARE;
    }

    function _checkDelegateCall() private view {
        require(address(this) != self);
    }

    function setVault(address newVault) public onlyOwner {
        require(newVault != address(0), "HD: zero address");
        _vault = newVault;
    }

    function withdrawETH(
        address recipient,
        uint256 amount
    ) external nonReentrant onlyOwner {
        recipient.safeTransferETH(amount);
        emit LogWithdrawETH(recipient, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}

    uint256[50] private __gap;
}
