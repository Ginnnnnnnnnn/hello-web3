package service

import (
	"context"
	"fmt"
	"sync"

	"github.com/ProjectsTask/EasySwapBase/chain"
	"github.com/ProjectsTask/EasySwapBase/chain/chainclient"
	"github.com/ProjectsTask/EasySwapBase/ordermanager"
	"github.com/ProjectsTask/EasySwapBase/stores/xkv"
	"github.com/pkg/errors"
	"github.com/zeromicro/go-zero/core/stores/cache"
	"github.com/zeromicro/go-zero/core/stores/kv"
	"github.com/zeromicro/go-zero/core/stores/redis"
	"gorm.io/gorm"

	"github.com/ProjectsTask/EasySwapSync/service/orderbookindexer"

	"github.com/ProjectsTask/EasySwapSync/model"
	"github.com/ProjectsTask/EasySwapSync/service/collectionfilter"
	"github.com/ProjectsTask/EasySwapSync/service/config"
)

type Service struct {
	ctx              context.Context            // 上下文
	config           *config.Config             // 配置信息
	kvStore          *xkv.Store                 // Redis
	db               *gorm.DB                   // Mysql
	wg               *sync.WaitGroup            // 等待
	collectionFilter *collectionfilter.Filter   // 过滤器
	orderbookIndexer *orderbookindexer.Service  // 订单簿服务
	orderManager     *ordermanager.OrderManager // 订单管理器
}

func New(ctx context.Context, cfg *config.Config) (*Service, error) {
	// 初始化Redis
	var kvConf kv.KvConf
	for _, con := range cfg.Kv.Redis {
		kvConf = append(kvConf, cache.NodeConf{
			RedisConf: redis.RedisConf{
				Host: con.Host,
				Type: con.Type,
				Pass: con.Pass,
			},
			Weight: 2,
		})
	}
	kvStore := xkv.NewStore(kvConf)
	// 初始化mysql
	var err error
	db := model.NewDB(cfg.DB)
	// 初始化过滤器
	collectionFilter := collectionfilter.New(ctx, db, cfg.ChainCfg.Name, cfg.ProjectCfg.Name)
	// 初始化管理器
	orderManager := ordermanager.New(ctx, db, kvStore, cfg.ChainCfg.Name, cfg.ProjectCfg.Name)
	// 初始化链客户端
	var orderbookSyncer *orderbookindexer.Service
	var chainClient chainclient.ChainClient
	fmt.Println("chainClient url:" + cfg.AnkrCfg.HttpsUrl + cfg.AnkrCfg.ApiKey)
	switch cfg.ChainCfg.ID {
	case chain.EthChainID, chain.OptimismChainID, chain.SepoliaChainID:
		// 以太坊客户端
		chainClient, err = chainclient.New(int(cfg.ChainCfg.ID), cfg.AnkrCfg.HttpsUrl+cfg.AnkrCfg.ApiKey)
		if err != nil {
			return nil, errors.Wrap(err, "failed on create evm client")
		}
		orderbookSyncer = orderbookindexer.New(ctx, cfg, db, kvStore, chainClient, cfg.ChainCfg.ID, cfg.ChainCfg.Name, orderManager)
	}
	// 设置结构体
	manager := Service{
		ctx:              ctx,
		config:           cfg,
		db:               db,
		kvStore:          kvStore,
		collectionFilter: collectionFilter,
		orderbookIndexer: orderbookSyncer,
		orderManager:     orderManager,
		wg:               &sync.WaitGroup{},
	}
	// 返回
	return &manager, nil
}

func (s *Service) Start() error {
	// 不要移动位置
	if err := s.collectionFilter.PreloadCollections(); err != nil {
		return errors.Wrap(err, "failed on preload collection to filter")
	}
	// 启动链客户端
	s.orderbookIndexer.Start()
	// 启动订单管理器
	s.orderManager.Start()
	return nil
}
