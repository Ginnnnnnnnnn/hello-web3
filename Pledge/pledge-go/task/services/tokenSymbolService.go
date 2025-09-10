package services

import (
	"encoding/json"
	"errors"
	"os"
	"pledge-backend/config"
	abifile "pledge-backend/contract/abi"
	"pledge-backend/db"
	"pledge-backend/log"
	"pledge-backend/task/models"
	"pledge-backend/utils"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"gorm.io/gorm"
)

type TokenSymbol struct{}

func NewTokenSymbol() *TokenSymbol {
	return &TokenSymbol{}
}

// 更新代币名称
func (s *TokenSymbol) UpdateContractSymbol() {
	// 查询所有代币信息
	var tokens []models.TokenInfo
	db.Mysql.Table("token_info").Find(&tokens)
	// 遍历代币信息
	for _, t := range tokens {
		var err error
		var symbol string
		// 校验
		if t.Token == "" {
			log.Logger.Sugar().Error("UpdateContractSymbol token empty", t.Symbol, t.ChainId)
			continue
		}
		if t.ChainId == config.Config.TestNet.ChainId {
			// 查询代币名称
			symbol, err = s.GetContractSymbolOnTestNet(t.Token, config.Config.TestNet.NetUrl)
			if err != nil {
				log.Logger.Sugar().Error("UpdateContractSymbol err ", t.Symbol, t.ChainId, err)
				continue
			}
		} else if t.ChainId == config.Config.MainNet.ChainId {
			// 判断abi文件是否存在
			if t.AbiFileExist == 0 {
				// 远程获取ABI文件
				err = s.GetRemoteAbiFileByToken(t.Token, t.ChainId)
				if err != nil {
					log.Logger.Sugar().Error("UpdateContractSymbol GetRemoteAbiFileByToken err ", t.Symbol, t.ChainId, err)
					continue
				}
			}
			// 查询代币名称
			symbol, err = s.GetContractSymbolOnMainNet(t.Token, config.Config.MainNet.NetUrl)
			if err != nil {
				log.Logger.Sugar().Error("UpdateContractSymbol err ", t.Symbol, t.ChainId, err)
				continue
			}
		} else {
			log.Logger.Sugar().Error("UpdateContractSymbol chain_id err ", t.Symbol, t.ChainId)
			continue
		}
		// 处理代币名称
		hasNewData, err := s.HandleSymbolData(t.Token, t.ChainId, symbol)
		if !hasNewData || err != nil {
			log.Logger.Sugar().Error("UpdateContractSymbol CheckSymbolData err ", err)
			continue
		}
	}
}

// 获取远程abi文件
func (s *TokenSymbol) GetRemoteAbiFileByToken(token, chainId string) error {

	// url := "https://api.bscscan.com/api?module=contract&action=getabi&apikey=HJ3WS4N88QJ6S7PQ8D89BD49IZIFP1JFER&address=" + token
	url := "https://api-sepolia.etherscan.io/api?module=contract&action=getabi&address=" + token

	res, err := utils.HttpGet(url, map[string]string{})
	if err != nil {
		log.Logger.Error(err.Error())
		return err
	}

	resStr := s.FormatAbiJsonStr(string(res))

	abiJson := models.AbiJson{}
	err = json.Unmarshal([]byte(resStr), &abiJson)
	if err != nil {
		log.Logger.Error(err.Error())
		return err
	}

	if abiJson.Status != "1" {
		log.Logger.Sugar().Error("get remote abi file failed: status 0 ", resStr)
		return errors.New("get remote abi file failed: status 0 ")
	}

	// marshal and format
	abiJsonBytes, err := json.MarshalIndent(abiJson.Result, "", "\t")
	if err != nil {
		log.Logger.Error(err.Error())
		return err
	}

	newAbiFile := abifile.GetCurrentAbPathByCaller() + "/" + token + ".abi"

	err = os.WriteFile(newAbiFile, abiJsonBytes, 0777)
	if err != nil {
		log.Logger.Error(err.Error())
		return err
	}

	err = db.Mysql.Table("token_info").Where("token=? and chain_id=?", token, chainId).Updates(map[string]interface{}{
		"abi_file_exist": 1,
	}).Debug().Error
	if err != nil {
		return err
	}
	return nil
}

// FormatAbiJsonStr format the abi string
func (s *TokenSymbol) FormatAbiJsonStr(result string) string {
	resStr := strings.Replace(result, `\`, ``, -1)
	resStr = strings.Replace(result, `\"`, `"`, -1)
	resStr = strings.Replace(resStr, `"[{`, `[{`, -1)
	resStr = strings.Replace(resStr, `}]"`, `}]`, -1)
	return resStr
}

// 获取合同代币-主网
func (s *TokenSymbol) GetContractSymbolOnMainNet(token, network string) (string, error) {
	ethereumConn, err := ethclient.Dial(network)
	if nil != err {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	abiStr, err := abifile.GetAbiByToken(token)
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	parsed, err := abi.JSON(strings.NewReader(abiStr))
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	contract := bind.NewBoundContract(common.HexToAddress(token), parsed, ethereumConn, ethereumConn, ethereumConn)
	res := make([]interface{}, 0)
	err = contract.Call(nil, &res, "symbol")
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", err)
		return "", err
	}

	return res[0].(string), nil
}

// 获取代币名称-测试网
func (s *TokenSymbol) GetContractSymbolOnTestNet(token, network string) (string, error) {
	// 链接ethereum
	ethereumConn, err := ethclient.Dial(network)
	if nil != err {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	// 读取erc20 abi
	abiStr, err := abifile.GetAbiByToken("erc20")
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	// 转换 abi json
	parsed, err := abi.JSON(strings.NewReader(abiStr))
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	// 加载合约
	contract := bind.NewBoundContract(common.HexToAddress(token), parsed, ethereumConn, ethereumConn, ethereumConn)
	// 获取代币名称
	res := make([]interface{}, 0)
	err = contract.Call(nil, &res, "symbol")
	if err != nil {
		log.Logger.Sugar().Error("GetContractSymbolOnMainNet err ", token, err)
		return "", err
	}
	// 返回
	return res[0].(string), nil
}

// 处理代币名称数据
func (s *TokenSymbol) HandleSymbolData(token, chainId, symbol string) (bool, error) {
	// 获取redis代币名称
	redisKey := "token_info:" + chainId + ":" + token
	redisTokenInfoBytes, err := db.RedisGet(redisKey)
	if err != nil {
		log.Logger.Error(err.Error())
		return false, err
	}
	// 判断redis中是否存在
	if len(redisTokenInfoBytes) <= 0 {
		// 保存代币名称信息
		err = s.SaveTokenInfo(token, chainId)
		if err != nil {
			log.Logger.Error(err.Error())
		}
		// 保存代币名称到redis
		err = db.RedisSet(redisKey, models.RedisTokenInfo{
			Token:   token,
			ChainId: chainId,
			Symbol:  symbol,
		}, 0)
		if err != nil {
			log.Logger.Error(err.Error())
			return false, err
		}
	} else {
		// 转换redis数据到结构体
		redisTokenInfo := models.RedisTokenInfo{}
		err = json.Unmarshal(redisTokenInfoBytes, &redisTokenInfo)
		if err != nil {
			log.Logger.Error(err.Error())
			return false, err
		}
		// 设置最新名称
		if redisTokenInfo.Symbol == symbol {
			return false, nil
		}
		redisTokenInfo.Symbol = symbol
		err = db.RedisSet(redisKey, redisTokenInfo, 0)
		if err != nil {
			log.Logger.Error(err.Error())
			return true, err
		}
	}
	return true, nil
}

// 保存代币名称信息
func (s *TokenSymbol) SaveTokenInfo(token, chainId string) error {
	tokenInfo := models.TokenInfo{}
	err := db.Mysql.Table("token_info").Where("token=? and chain_id=?", token, chainId).First(&tokenInfo).Debug().Error
	if err != nil {
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
