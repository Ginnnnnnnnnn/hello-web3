package models

import (
	"encoding/json"
	"pledge-backend/api/models/request"
	"pledge-backend/db"
	"pledge-backend/task/models"
)

type Pool struct {
	PoolID                 int      `json:"pool_id"`
	SettleTime             string   `json:"settleTime"`
	EndTime                string   `json:"endTime"`
	InterestRate           string   `json:"interestRate"`
	MaxSupply              string   `json:"maxSupply"`
	LendSupply             string   `json:"lendSupply"`
	BorrowSupply           string   `json:"borrowSupply"`
	MartgageRate           string   `json:"martgageRate"`
	LendToken              string   `json:"lendToken"`
	LendTokenSymbol        string   `json:"lend_token_symbol"`
	BorrowToken            string   `json:"borrowToken"`
	BorrowTokenSymbol      string   `json:"borrow_token_symbol"`
	State                  string   `json:"state"`
	SpCoin                 string   `json:"spCoin"`
	JpCoin                 string   `json:"jpCoin"`
	AutoLiquidateThreshold string   `json:"autoLiquidateThreshold"`
	Pooldata               PoolData `json:"pooldata"`
}

func NewPool() *Pool {
	return &Pool{}
}

// 检索借贷池
func (p *Pool) Pagination(req *request.Search, whereCondition string) (int64, []Pool, error) {
	var total int64
	pools := []Pool{}
	poolBase := []models.PoolBase{}
	// 检索借贷池
	db.Mysql.Table("poolbases").Where(whereCondition).Count(&total)
	err := db.Mysql.Table("poolbases").Where(whereCondition).Order("pool_id desc").Limit(req.PageSize).Offset((req.Page - 1) * req.PageSize).Find(&poolBase).Debug().Error
	if err != nil {
		return 0, nil, err
	}
	// 转换结构体
	for _, b := range poolBase {
		poolData := PoolData{}
		err = db.Mysql.Table("pooldata").Where("chain_id=?", req.ChainID).First(&poolData).Debug().Error
		if err != nil {
			return 0, nil, err
		}
		var lendToken models.LendToken
		_ = json.Unmarshal([]byte(b.LendTokenInfo), &lendToken)
		var borrowToken models.BorrowToken
		_ = json.Unmarshal([]byte(b.BorrowTokenInfo), &borrowToken)
		pools = append(pools, Pool{
			PoolID:                 b.PoolId,
			SettleTime:             b.SettleTime,
			EndTime:                b.EndTime,
			InterestRate:           b.InterestRate,
			MaxSupply:              b.MaxSupply,
			LendSupply:             b.LendSupply,
			BorrowSupply:           b.BorrowSupply,
			MartgageRate:           b.MartgageRate,
			LendToken:              lendToken.TokenName,
			BorrowToken:            borrowToken.TokenName,
			State:                  b.State,
			SpCoin:                 b.SpCoin,
			JpCoin:                 b.JpCoin,
			AutoLiquidateThreshold: b.AutoLiquidateThreshold,
			Pooldata:               poolData,
		})
	}
	return total, pools, nil
}
