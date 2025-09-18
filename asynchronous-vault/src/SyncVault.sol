//SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable, IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/*
 *         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%=::::::=%@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*=#=--=*=*@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:*=    =#:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@:@@    @@:@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*-.    .-*@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@*        *@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@.         .@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@*  Amphor  *@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@*==========#@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@+==========*@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@*   Sync   *@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@%  Vault  %@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@=        +@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%       %@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@=      =@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@%     .@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@=    =@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@%----%@@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@%+:::::+%@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@########@@@@@@@@@@@@@@@@@@@@@
 *         @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
 *
 *            d8888                        888
 *           d88888                        888
 *          d88P888                        888
 *         d88P 888 88888b.d88b.  88888b.  88888b.   .d88b.  888d888
 *        d88P  888 888 "888 "88b 888 "88b 888 "88b d88""88b 888P"
 *       d88P   888 888  888  888 888  888 888  888 888  888 888
 *      d8888888888 888  888  888 888 d88P 888  888 Y88..88P 888
 *     d88P     888 888  888  888 88888P"  888  888  "Y88P"  888.io
 *                                888
 *                                888
 *                                888
 */

using Math for uint256; // only used for `mulDiv` operations.
using SafeERC20 for IERC20; // `safeTransfer` and `safeTransferFrom`

// ERC-20 permit函数参数结构体，用于离线授权许可
struct PermitParams {
    uint256 value; // 授权额度
    uint256 deadline; // 签名的过期时间
    uint8 v; // 签名恢复参数
    bytes32 r; // 签名的一部分
    bytes32 s; // 签名的另一部分
}

uint16 constant MAX_FEES = 3000; // 30%

abstract contract SyncVault is
    IERC4626,
    Ownable2StepUpgradeable,
    ERC20PermitUpgradeable,
    ERC20PausableUpgradeable
{
    // =================== 状态变量 ===================

    // 费率 BPS（最大 MAX_FEES=3000，即 30%）
    uint16 public feesInBps;
    // 最大回撤阈值（默认 30%）
    uint16 internal _maxDrawdown;
    // 资产精度
    uint8 private _underlyingDecimals;
    // 资产代币
    IERC20 internal _asset;
    // 金库开放状态
    bool public vaultIsOpen;
    // 上次保存资产余额
    uint256 public lastSavedBalance;

    // =================== 事件 ===================

    event EpochStart(
        uint256 indexed timestamp,
        uint256 lastSavedBalance,
        uint256 totalShares
    );

    event EpochEnd(
        uint256 indexed timestamp,
        uint256 lastSavedBalance,
        uint256 returnedAssets,
        uint256 fees,
        uint256 totalShares
    );

    event FeesChanged(uint16 oldFees, uint16 newFees);

    // =================== 错误 ===================

    error VaultIsClosed();
    error VaultIsOpen();
    error FeesTooHigh();
    error ERC4626ExceededMaxDeposit(
        address receiver,
        uint256 assets,
        uint256 max
    );
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
    error ERC4626ExceededMaxWithdraw(
        address owner,
        uint256 assets,
        uint256 max
    );
    error ERC4626ExceededMaxRedeem(address owner, uint256 shares, uint256 max);
    error VaultIsEmpty(); // We cannot start an epoch with an empty vault
    error MaxDrawdownReached();
    error PermitFailed(); // see

    // =================== 修饰器 ===================

    modifier whenClosed() {
        if (vaultIsOpen) revert VaultIsOpen();
        _;
    }

    // =================== 初始化 ===================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint16 fees,
        address owner,
        IERC20 underlying,
        uint256 bootstrapAmount,
        string memory name,
        string memory symbol
    ) public virtual onlyInitializing {
        if (fees > MAX_FEES) revert FeesTooHigh();
        feesInBps = fees;
        vaultIsOpen = true;
        _maxDrawdown = 3000; // 30%
        _asset = underlying;
        _underlyingDecimals = uint8(
            IERC20Metadata(address(underlying)).decimals()
        );
        // 初始化 owner 和 份额币 信息
        __ERC20_init(name, symbol);
        __Ownable_init(owner);
        __ERC20Permit_init(name);
        __ERC20Pausable_init();
        // 质押初始份额
        deposit(bootstrapAmount, owner);
    }

    // =================== 合约设置 ===================

    /**
     * @dev 暂停
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 取消暂停
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 设置绩效费
     * @notice 只能由合同的所有者调用，不能超过30%（BPS为3000）
     * @param newFee 新效费
     */
    function setFee(uint16 newFee) external onlyOwner {
        if (!vaultIsOpen) revert VaultIsClosed();
        if (newFee > MAX_FEES) revert FeesTooHigh();
        feesInBps = newFee;
        emit FeesChanged(feesInBps, newFee);
    }

    /**
     * @dev 设置最大提款
     * @notice 只能由合同的所有者调用
     * @param newMaxDrawdown 最大提款
     */
    function setMaxDrawdown(uint16 newMaxDrawdown) external onlyOwner {
        if (newMaxDrawdown > 10_000) revert MaxDrawdownReached();
        _maxDrawdown = newMaxDrawdown;
    }

    /**
     * @dev 获取资产代币地址
     */
    function asset() public view returns (address) {
        return address(_asset);
    }

    function open(uint256 assetReturned) external virtual;
    function close() external virtual;

    // =================== 功能方法 ===================

    /**
     * @dev 撤回
     * @notice 撤回指定数量资产，销毁对应数量份额
     * @param assets 资产数量
     * @param receiver 资产接收者
     * @param owner owner 份额拥有者
     * @return 销毁份额数量
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external whenNotPaused returns (uint256) {
        // 校验 开放状态 和 最大撤回金额
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }
        // 计算份额
        uint256 sharesAmount = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, sharesAmount);
        // 返回
        return sharesAmount;
    }

    /**
     * @dev 兑换
     * @notice 销毁指定数量份额，撤回对应数量资产
     * @param shares 份额
     * @param receiver 接收者
     * @param owner 份额拥有者
     * @return 兑换资产数量
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public whenNotPaused returns (uint256) {
        // 校验 开放状态 和 最大兑换份额
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }
        // 计算资产
        uint256 assetsAmount = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assetsAmount, shares);
        // 返回
        return assetsAmount;
    }

    /**
     * @dev 存款-离线许可授权
     * @param assets 资产数量
     * @param receiver 份额接收地址
     * @param permitParams 离线许可参数
     * @return 份额数量
     */
    function depositWithPermit(
        uint256 assets,
        address receiver,
        PermitParams calldata permitParams
    ) external returns (uint256) {
        address _msgSender = _msgSender();
        // 检查授权余额
        if (_asset.allowance(_msgSender, address(this)) < assets) {
            // 余额不够，执行授权
            execPermit(_msgSender, address(this), permitParams);
        }
        // 存款
        return deposit(assets, receiver);
    }

    /**
     * @dev 存款
     * @notice 存款指定数量份额，铸造对应数量份额
     * @param assets 资产数量
     * @param receiver 份额接收地址
     * @return 份额数量
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public whenNotPaused returns (uint256) {
        // 校验 开放状态 和 最大存款金额
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }
        // 计算份额
        uint256 sharesAmount = previewDeposit(assets);
        // 存款 和 铸造份额
        _deposit(_msgSender(), receiver, assets, sharesAmount);
        // 返回
        return sharesAmount;
    }

    /**
     * @dev 铸造
     * @notice 铸造指定数量份额，存款所需数量代币
     * @param shares 份额数量
     * @param receiver 份额接收地址
     * @return 资产数量
     */
    function mint(
        uint256 shares,
        address receiver
    ) public whenNotPaused returns (uint256) {
        // 校验 开放状态 和 最大存款金额
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        // 计算资产
        uint256 assetsAmount = previewMint(shares);
        // 存款 和 铸造份额
        _deposit(_msgSender(), receiver, assetsAmount, shares);
        // 返回
        return assetsAmount;
    }

    /**
     * @dev 计算份额
     * @param assets 资产
     * @return 份额
     */
    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev 计算资产
     * @param owner 份额拥有者
     * @return 资产
     */
    function sharesBalanceInAsset(address owner) public view returns (uint256) {
        return convertToAssets(balanceOf(owner));
    }

    /**
     * @dev 计算资产
     * @param shares 份额
     * @return 资产
     */
    function convertToAssets(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev 最大存款
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大可铸造数量
     */
    function maxDeposit(address) public view returns (uint256) {
        return vaultIsOpen && !paused() ? type(uint256).max : 0;
    }

    /**
     * @dev 最大铸造
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大可铸造数量
     */
    function maxMint(address) public view returns (uint256) {
        return vaultIsOpen && !paused() ? type(uint256).max : 0;
    }

    /**
     * @dev 最大撤回
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大可撤回资产
     */
    function maxWithdraw(address owner) public view returns (uint256) {
        return
            vaultIsOpen && !paused()
                ? _convertToAssets(balanceOf(owner), Math.Rounding.Floor)
                : 0;
    }

    /**
     * @dev 最大兑换
     * @notice 如果保险库被锁定或暂停，则为0。
     * @return 最大可兑换份额
     */
    function maxRedeem(address owner) public view returns (uint256) {
        return vaultIsOpen && !paused() ? balanceOf(owner) : 0;
    }

    /**
     * @dev 计算份额-存款
     * @param assets 资产
     * @return 份额
     */
    function previewDeposit(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    /**
     * @dev 计算份额-铸造
     * @param shares 份额
     * @return 资产
     */
    function previewMint(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Ceil);
    }

    /**
     * @dev 计算份额-撤回
     * @param assets 资产
     * @return 份额
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @dev 计算资产-兑换
     * @param shares 份额
     * @return 资产
     */
    function previewRedeem(uint256 shares) public view returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Floor);
    }

    /**
     * @dev 金库总资产
     */
    function totalAssets() public view returns (uint256) {
        if (vaultIsOpen) return _asset.balanceOf(address(this));
        else return _asset.balanceOf(address(this)) + lastSavedBalance;
    }

    /**
     * @dev 存款 和 铸造份额
     * @param caller 调用者
     * @param receiver 份额接收者
     * @param assets 存款资产数量
     * @param shares 铸造份额数量
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        // 转账资产到合约
        _asset.safeTransferFrom(caller, address(this), assets);
        // mint份额
        _mint(receiver, shares);
        // 发送存款事件
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev 赎回 和 销毁份额
     * @param caller 发起者地址
     * @param receiver 资产接收者
     * @param owner 份额拥有者
     * @param assets 资产
     * @param shares 份额
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal {
        // 代替别人赎回，检查授权
        if (caller != owner) _spendAllowance(owner, caller, shares);
        // burn份额
        _burn(owner, shares);
        // 转账资产到发送者
        _asset.safeTransfer(receiver, assets);
        // 发送赎回事件
        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev 更新股份信息
     * @param from 拥有者
     * @param to 接收者
     * @param value 金额
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal virtual override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        ERC20PausableUpgradeable._update(from, to, value);
    }

    /**
     * @dev 执行授权
     * @param owner 拥有者
     * @param spender 授权接收地址
     * @param permitParams 离线签名参数
     */
    function execPermit(
        address owner,
        address spender,
        PermitParams calldata permitParams
    ) internal {
        ERC20Permit(address(_asset)).permit(
            owner,
            spender,
            permitParams.value,
            permitParams.deadline,
            permitParams.v,
            permitParams.r,
            permitParams.s
        );
        if (_asset.allowance(owner, spender) != permitParams.value) {
            revert PermitFailed();
        }
    }

    /**
     * @dev 计算份额
     * @param assets 资产
     * @param rounding 舍入方式
     * @return 份额
     */
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        // 计算份额，+1 保证初始资金 0 时平滑过渡
        // 资产 * ( 当前总份额 / 金库总资产 )
        return assets.mulDiv(totalSupply() + 1, totalAssets() + 1, rounding);
    }

    /**
     * @dev 计算资产
     * @param shares 份额
     * @param rounding 舍入方式
     * @return 资产
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        // 计算资产，+1 保证初始资金 0 时平滑过渡
        // 份额 * ( 金库总资产 / 当前总份额 )
        return shares.mulDiv(totalAssets() + 1, totalSupply() + 1, rounding);
    }

    /**
     * @dev 资产精度
     */
    function decimals()
        public
        view
        virtual
        override(ERC20Upgradeable, IERC20Metadata)
        returns (uint8)
    {
        return _underlyingDecimals;
    }
}
