//SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable2StepUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {
    ERC20Upgradeable,
    IERC20
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20Metadata } from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Initializable } from
    "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20Permit } from
    "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

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

/*
 * ########
 * # LIBS #
 * ########
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

    // 绩效费 BPS（最大 MAX_FEES=3000，即 30%）
    uint16 public feesInBps;
    // 最大提款阈值（默认 30%）
    uint16 internal _maxDrawdown;
    // 资产精度
    uint8 private _underlyingDecimals;
    // 底层资产
    IERC20 internal _asset;
    // 金库是否开放
    bool public vaultIsOpen;
    // 上次保存资产余额
    uint256 public lastSavedBalance;

    // =================== 事件 ===================

    event EpochStart(
        uint256 indexed timestamp, uint256 lastSavedBalance, uint256 totalShares
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
        address receiver, uint256 assets, uint256 max
    );
    error ERC4626ExceededMaxMint(address receiver, uint256 shares, uint256 max);
    error ERC4626ExceededMaxWithdraw(address owner, uint256 assets, uint256 max);
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
    )
        public
        virtual
        onlyInitializing
    {
        if (fees > MAX_FEES) revert FeesTooHigh();
        feesInBps = fees;
        vaultIsOpen = true;
        _maxDrawdown = 3000; // 30%
        _asset = underlying;
        _underlyingDecimals =
            uint8(IERC20Metadata(address(underlying)).decimals());
        // 初始化 owner 和 份额币 信息
        __ERC20_init(name, symbol);
        __Ownable_init(owner);
        __ERC20Permit_init(name);
        __ERC20Pausable_init();
        // 质押初始份额
        deposit(bootstrapAmount, owner);
    }

    /**
     * @dev The `withdraw` function is used to withdraw the specified underlying
     * assets amount in exchange of a proportional amount of shares.
     * @param assets The underlying assets amount to be converted into shares.
     * @param receiver The address of the shares receiver.
     * @param owner The address of the owner.
     * @return Amount of shares received in exchange of the specified underlying
     * assets amount.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        external
        whenNotPaused
        returns (uint256)
    {
        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);
        }

        uint256 sharesAmount = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, sharesAmount);

        return sharesAmount;
    }

    /*
     * #################################
     * # Pausability RELATED FUNCTIONS #
     * #################################
    */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*
     * ######################################
     * # AMPHOR SYNTHETIC RELATED FUNCTIONS #
     * ######################################
    */

    /**
     * @dev The `setFee` function is used to modify the protocol fees.
     * @notice The `setFee` function is used to modify the perf fees.
     * It can only be called by the owner of the contract (`onlyOwner`
     * modifier).
     * It can't exceed 30% (3000 in BPS).
     * @param newFee The new perf fees to be applied.
     */
    function setFee(uint16 newFee) external onlyOwner {
        if (!vaultIsOpen) revert VaultIsClosed();
        if (newFee > MAX_FEES) revert FeesTooHigh();
        feesInBps = newFee;
        emit FeesChanged(feesInBps, newFee);
    }

    function setMaxDrawdown(uint16 newMaxDrawdown) external onlyOwner {
        if (newMaxDrawdown > 10_000) revert MaxDrawdownReached();
        _maxDrawdown = newMaxDrawdown;
    }

    function open(uint256 assetReturned) external virtual;
    function close() external virtual;

    /*
     * #################################
     * #   Permit RELATED FUNCTIONS    #
     * #################################
    */

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
    )
        external
        returns (uint256)
    {
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
     * @notice 存款指定数量代币换取份额
     * @param assets 资产数量
     * @param receiver 份额接收地址
     * @return 份额数量
     */
    function deposit(
        uint256 assets,
        address receiver
    )
        public
        whenNotPaused
        returns (uint256)
    {
        // 校验 开发状态 和 最大存款金额
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
     * @notice 铸造指定份额数量的代币
     * @param shares 份额数量
     * @param receiver 份额接收地址
     * @return 资产数量
     */
    function mint(
        uint256 shares,
        address receiver
    )
        public
        whenNotPaused
        returns (uint256)
    {
        // 校验 开发状态 和 最大存款金额
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        // 计算份额
        uint256 assetsAmount = previewMint(shares);
        // 存款 和 铸造份额
        _deposit(_msgSender(), receiver, assetsAmount, shares);
        // 返回
        return assetsAmount;
    }

    /**
     * @dev The `redeem` function is used to redeem the specified amount of
     * shares in exchange of the corresponding underlying assets amount from
     * owner.
     * @param shares The shares amount to be converted into underlying assets.
     * @param receiver The address of the shares receiver.
     * @param owner The address of the owner.
     * @return Amount of underlying assets received in exchange of the specified
     * amount of shares.
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        whenNotPaused
        returns (uint256)
    {
        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);
        }

        uint256 assetsAmount = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assetsAmount, shares);

        return assetsAmount;
    }

    // @return address of the underlying asset.
    function asset() public view returns (address) {
        return address(_asset);
    }

    // @dev See {IERC4626-convertToShares}.
    function convertToShares(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Floor);
    }

    function sharesBalanceInAsset(address owner)
        public
        view
        returns (uint256)
    {
        return convertToAssets(balanceOf(owner));
    }

    // @dev See {IERC4626-convertToAssets}.
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
     * @dev See {IERC4626-maxWithdraw}.
     * @notice If the function is called during the lock period the maxWithdraw
     * is `0`.
     * @return Amount of the maximum number of withdrawable underlying assets.
     */
    function maxWithdraw(address owner) public view returns (uint256) {
        return vaultIsOpen && !paused()
            ? _convertToAssets(balanceOf(owner), Math.Rounding.Floor)
            : 0;
    }

    /**
     * @dev See {IERC4626-maxRedeem}.
     * @notice If the function is called during the lock period the maxRedeem is
     * `0`;
     * @param owner The address of the owner.
     * @return Amount of the maximum number of redeemable shares.
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
     * @dev See {IERC4626-previewWithdraw}
     */
    function previewWithdraw(uint256 assets) public view returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Ceil);
    }

    /**
     * @dev See {IERC4626-previewRedeem}
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
    )
        internal
    {
        // If _asset is ERC777, transferFrom can trigger a reentrancy BEFORE the
        // transfer happens through the tokensToSend hook. On the other hand,
        // the tokenReceived hook, that is triggered after the transfer,calls
        // the vault, which is assumed not malicious.
        //
        // Conclusion: we need to do the transfer before we mint so that any
        // reentrancy would happen before the assets are transferred and before
        // the shares are minted, which is a valid state.
        // slither-disable-next-line reentrancy-no-eth
        _asset.safeTransferFrom(caller, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev The function `_withdraw` is used to withdraw the specified
     * underlying assets amount in exchange of a proportionnal amount of shares
     * by
     * specifying all the params.
     * @notice The `withdraw` function is used to withdraw the specified
     * underlying assets amount in exchange of a proportionnal amount of shares.
     * @param receiver The address of the shares receiver.
     * @param owner The address of the owner.
     * @param assets The underlying assets amount to be converted into shares.
     * @param shares The shares amount to be converted into underlying assets.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    )
        internal
    {
        if (caller != owner) _spendAllowance(owner, caller, shares);

        _burn(owner, shares);
        _asset.safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    function _update(
        address from,
        address to,
        uint256 value
    )
        internal
        virtual
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
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
    )
        internal
    {
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
    )
        internal
        view
        returns (uint256)
    {
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
    )
        internal
        view
        returns (uint256)
    {
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
