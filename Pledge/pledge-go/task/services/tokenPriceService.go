package services

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"pledge-backend/config"
	"pledge-backend/contract/bindings"
	"pledge-backend/db"
	"pledge-backend/log"
	serviceCommon "pledge-backend/task/common"
	"pledge-backend/task/models"
	"pledge-backend/utils"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/shopspring/decimal"
	"gorm.io/gorm"
)

type TokenPrice struct{}

func NewTokenPrice() *TokenPrice {
	return &TokenPrice{}
}

// 更新合约价格
func (s *TokenPrice) UpdateContractPrice() {
	// 查询所有代币信息
	var tokens []models.TokenInfo
	db.Mysql.Table("token_info").Find(&tokens)
	// 遍历代币信息
	for _, t := range tokens {
		var err error
		var price int64 = 0
		// 校验
		if t.Token == "" {
			log.Logger.Sugar().Error("UpdateContractPrice token empty ", t.Symbol, t.ChainId)
			continue
		}
		// 判断链ID
		if t.ChainId == config.Config.TestNet.ChainId {
			// 获取价格
			price, err = s.GetTestNetTokenPrice(t.Token)
			if err != nil {
				log.Logger.Sugar().Error("UpdateContractPrice err ", t.Symbol, t.ChainId, err)
				continue
			}
		} else {
			log.Logger.Sugar().Error("UpdateContractPrice chain_id err ", t.Symbol, t.ChainId)
			continue
		}
		// 处理价格信息
		hasNewData, err := s.HandlePriceData(t.Token, t.ChainId, utils.Int64ToString(price))
		if !hasNewData || err != nil {
			log.Logger.Sugar().Error("UpdateContractPrice CheckPriceData err ", err)
			continue
		}
	}
}

// 获取合约价格-主网
func (s *TokenPrice) GetMainNetTokenPrice(token string) (int64, error) {
	ethereumConn, err := ethclient.Dial(config.Config.MainNet.NetUrl)
	if nil != err {
		log.Logger.Error(err.Error())
		return 0, err
	}

	bscPledgeOracleMainNetToken, err := bindings.NewBscPledgeOracleMainnetToken(common.HexToAddress(config.Config.MainNet.BscPledgeOracleToken), ethereumConn)
	if nil != err {
		log.Logger.Error(err.Error())
		return 0, err
	}

	price, err := bscPledgeOracleMainNetToken.GetPrice(nil, common.HexToAddress(token))
	if err != nil {
		log.Logger.Error(err.Error())
		return 0, err
	}

	return price.Int64(), nil
}

// 获取合约价格-测试网
func (s *TokenPrice) GetTestNetTokenPrice(token string) (int64, error) {
	ethereumConn, err := ethclient.Dial(config.Config.TestNet.NetUrl)
	if nil != err {
		log.Logger.Error(err.Error())
		return 0, err
	}
	// 获取语言机合约
	bscPledgeOracleTestnetToken, err := bindings.NewBscPledgeOracleTestnetToken(common.HexToAddress(config.Config.TestNet.BscPledgeOracleToken), ethereumConn)
	if nil != err {
		log.Logger.Error(err.Error())
		return 0, err
	}
	// 获取价格
	price, err := bscPledgeOracleTestnetToken.GetPrice(nil, common.HexToAddress(token))
	if nil != err {
		log.Logger.Error(err.Error())
		return 0, err
	}
	// 返回价格
	return price.Int64(), nil
}

// 处理价格信息
func (s *TokenPrice) HandlePriceData(token, chainId, price string) (bool, error) {
	// 读取redis价格
	redisKey := "token_info:" + chainId + ":" + token
	redisTokenInfoBytes, err := db.RedisGet(redisKey)
	if err != nil {
		log.Logger.Error(err.Error())
	}
	// 判断redis中是否存在价格信息
	if len(redisTokenInfoBytes) <= 0 {
		// 保存价格信息
		err = s.SaveTokenInfo(token, chainId)
		if err != nil {
			log.Logger.Error(err.Error())
		}
		// 保存价格信息到redis
		err = db.RedisSet(redisKey, models.RedisTokenInfo{
			Token:   token,
			ChainId: chainId,
			Price:   price,
		}, 0)
		if err != nil {
			log.Logger.Error(err.Error())
			return false, err
		}
	} else {
		// 转换redis中价格信息到结构体
		redisTokenInfo := models.RedisTokenInfo{}
		err = json.Unmarshal(redisTokenInfoBytes, &redisTokenInfo)
		if err != nil {
			log.Logger.Error(err.Error())
			return false, err
		}
		// 设置新价格
		if redisTokenInfo.Price == price {
			return false, nil
		}
		redisTokenInfo.Price = price
		err = db.RedisSet(redisKey, redisTokenInfo, 0)
		if err != nil {
			log.Logger.Error(err.Error())
			return true, err
		}
	}
	return true, nil
}

// 保存价格信息
func (s *TokenPrice) SaveTokenInfo(token, chainId string) error {
	// 查询价格信息
	tokenInfo := models.TokenInfo{}
	err := db.Mysql.Table("token_info").Where("token=? and chain_id=?", token, chainId).First(&tokenInfo).Debug().Error
	if err != nil {
		// 添加价格信息
		if errors.Is(err, gorm.ErrRecordNotFound) {
			tokenInfo = models.TokenInfo{}
			nowDateTime := utils.GetCurDateTimeFormat()
			tokenInfo.Token = token
			tokenInfo.ChainId = chainId
			tokenInfo.UpdatedAt = nowDateTime
			tokenInfo.CreatedAt = nowDateTime
			err = db.Mysql.Table("token_info").Create(tokenInfo).Debug().Error
			if err != nil {
				return err
			}
		} else {
			return err
		}
	}
	return nil
}

// SavePlgrPrice Saving price data to mysql if it has new price
func (s *TokenPrice) SavePlgrPrice() {
	priceStr, _ := db.RedisGetString("plgr_price")
	priceF, _ := decimal.NewFromString(priceStr)
	e8 := decimal.NewFromInt(100000000)
	priceF = priceF.Mul(e8)
	price := priceF.IntPart()

	ethereumConn, err := ethclient.Dial(config.Config.MainNet.NetUrl)
	if nil != err {
		log.Logger.Error(err.Error())
		return
	}
	bscPledgeOracleMainNetToken, err := bindings.NewBscPledgeOracleMainnetToken(common.HexToAddress(config.Config.MainNet.BscPledgeOracleToken), ethereumConn)
	if nil != err {
		log.Logger.Error(err.Error())
		return
	}

	privateKeyEcdsa, err := crypto.HexToECDSA(serviceCommon.PlgrAdminPrivateKey)
	if err != nil {
		log.Logger.Error(err.Error())
		return
	}

	auth, err := bind.NewKeyedTransactorWithChainID(privateKeyEcdsa, big.NewInt(utils.StringToInt64(config.Config.MainNet.ChainId)))
	if err != nil {
		log.Logger.Error(err.Error())
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	transactOpts := bind.TransactOpts{
		From:      auth.From,
		Nonce:     nil,
		Signer:    auth.Signer, // Method to use for signing the transaction (mandatory)
		Value:     big.NewInt(0),
		GasPrice:  nil,
		GasFeeCap: nil,
		GasTipCap: nil,
		GasLimit:  0,
		Context:   ctx,
		NoSend:    false, // Do all transact steps but do not send the transaction
	}

	_, err = bscPledgeOracleMainNetToken.SetPrice(&transactOpts, common.HexToAddress(config.Config.MainNet.PlgrAddress), big.NewInt(price))

	log.Logger.Sugar().Info("SavePlgrPrice ", err)

	a, d := s.GetMainNetTokenPrice(config.Config.MainNet.PlgrAddress)
	log.Logger.Sugar().Info("GetMainNetTokenPrice ", a, d)
}

// 保存plgr价格-测试网
func (s *TokenPrice) SavePlgrPriceTestNet() {
	price := 22222
	// 链接ethereum
	ethereumConn, err := ethclient.Dial(config.Config.TestNet.NetUrl)
	if nil != err {
		log.Logger.Error(err.Error())
		return
	}
	// 加载语言机合约
	bscPledgeOracleTestNetToken, err := bindings.NewBscPledgeOracleMainnetToken(common.HexToAddress(config.Config.TestNet.BscPledgeOracleToken), ethereumConn)
	if nil != err {
		log.Logger.Error(err.Error())
		return
	}
	// 加载私钥
	privateKeyEcdsa, err := crypto.HexToECDSA(serviceCommon.PlgrAdminPrivateKey)
	if err != nil {
		log.Logger.Error(err.Error())
		return
	}
	// 签名
	auth, err := bind.NewKeyedTransactorWithChainID(privateKeyEcdsa, big.NewInt(utils.StringToInt64(config.Config.TestNet.ChainId)))
	if err != nil {
		log.Logger.Error(err.Error())
		return
	}
	// 等待一段时间
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()
	// 设置语言机plgr代币价格
	transactOpts := bind.TransactOpts{
		From:      auth.From,
		Nonce:     nil,
		Signer:    auth.Signer, // Method to use for signing the transaction (mandatory)
		Value:     big.NewInt(0),
		GasPrice:  nil,
		GasFeeCap: nil,
		GasTipCap: nil,
		GasLimit:  0,
		Context:   ctx,
		NoSend:    false, // Do all transact steps but do not send the transaction
	}
	_, err = bscPledgeOracleTestNetToken.SetPrice(&transactOpts, common.HexToAddress(config.Config.TestNet.PlgrAddress), big.NewInt(int64(price)))
	log.Logger.Sugar().Info("SavePlgrPrice ", err)
	// 获取plgr代币价格
	a, d := s.GetTestNetTokenPrice(config.Config.TestNet.PlgrAddress)
	fmt.Println(a, d, 5555)
}
