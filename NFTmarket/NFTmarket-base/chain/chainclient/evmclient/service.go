package evmclient

import (
	"context"
	"math/big"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/pkg/errors"

	logTypes "github.com/ProjectsTask/EasySwapBase/chain/types"
)

type Service struct {
	client *ethclient.Client
}

// 创建以太坊客户端
func New(nodeUrl string) (*Service, error) {
	client, err := ethclient.Dial(nodeUrl)
	if err != nil {
		return nil, errors.Wrap(err, "failed on create client")
	}
	return &Service{
		client: client,
	}, nil
}

// 获取以太坊客户端
func (s *Service) Client() interface{} {
	return s.client
}

// 查询事件
func (s *Service) FilterLogs(ctx context.Context, q logTypes.FilterQuery) ([]interface{}, error) {
	// 收集合约地址
	var addresses []common.Address
	for _, addr := range q.Addresses {
		addresses = append(addresses, common.HexToAddress(addr))
	}
	// 收集Topics
	var topicsHash [][]common.Hash
	for _, topics := range q.Topics {
		var topicHash []common.Hash
		for _, topic := range topics {
			topicHash = append(topicHash, common.HexToHash(topic))
		}
		topicsHash = append(topicsHash, topicHash)
	}
	// 查询事件
	queryParam := ethereum.FilterQuery{
		FromBlock: q.FromBlock,
		ToBlock:   q.ToBlock,
		Addresses: addresses,
		Topics:    topicsHash,
	}
	logs, err := s.client.FilterLogs(ctx, queryParam)
	if err != nil {
		return nil, errors.Wrap(err, "failed on get events")
	}
	// 收集事件
	var logEvents []interface{}
	for _, log := range logs {
		logEvents = append(logEvents, log)
	}
	// 返回
	return logEvents, nil
}

// 获取指定区块事件
func (s *Service) BlockTimeByNumber(ctx context.Context, blockNum *big.Int) (uint64, error) {
	header, err := s.client.HeaderByNumber(ctx, blockNum)
	if err != nil {
		return 0, errors.Wrap(err, "failed on get block header")
	}

	return header.Time, nil
}

func (s *Service) CallContractByChain(ctx context.Context, param logTypes.CallParam) (interface{}, error) {
	return s.CallContract(ctx, param.EVMParam, param.BlockNumber)
}

func (s *Service) CallContract(ctx context.Context, msg ethereum.CallMsg, blockNumber *big.Int) ([]byte, error) {
	return s.client.CallContract(ctx, msg, blockNumber)
}

func (s *Service) BlockNumber() (uint64, error) {
	var err error
	blockNum, err := s.client.BlockNumber(context.Background())
	if err != nil {
		return 0, errors.Wrap(err, "failed on get evm block number")
	}

	return blockNum, nil
}

func (s *Service) BlockWithTxs(ctx context.Context, blockNumber uint64) (interface{}, error) {
	blockWithTxs, err := s.client.BlockByNumber(ctx, big.NewInt(int64(blockNumber)))
	if err != nil {
		return nil, errors.Wrap(err, "failed on get evm block")
	}
	return blockWithTxs, nil
}
