# Pledge定时任务

## 框架介绍

github.com/jasonlvhit/gocron 该定时任务库会在协程里执行任务，在执行耗时任务时，会按照定时时间开始执行，结束时间根据具体任务而定。

## 代码示例

 ```golang
 // 基础用法
 gocron.Every(1).Second().Do(tasks.Task)
 gocron.Every(1).Second().Do(tasks.Task2)
 gocron.Every(2).Seconds().Do(tasks.Task)
 gocron.Every(1).Minute().Do(tasks.Task)
 gocron.Every(2).Minutes().Do(tasks.Task)
 gocron.Every(1).Hour().Do(tasks.Task)
 gocron.Every(2).Hours().Do(tasks.Task)
 gocron.Every(1).Day().Do(tasks.Task)
 gocron.Every(2).Days().Do(tasks.Task)
 gocron.Every(1).Week().Do(tasks.Task)
 gocron.Every(2).Weeks().Do(tasks.Task)

 // 带参
 gocron.Every(1).Second().Do(tasks.TaskWithParams, "hello")

 // 特定日期
 gocron.Every(1).Monday().Do(tasks.Task)
 gocron.Every(1).Thursday().Do(tasks.Task)

 // 特定日期，特定时间
 gocron.Every(1).Day().At("10:30").Do(tasks.Task)
 gocron.Every(1).Monday().At("18:30").Do(tasks.Task)
 gocron.Every(1).Tuesday().At("18:30:59").Do(tasks.Task)

 // 立即开始
 gocron.Every(1).Hour().From(gocron.NextTick()).Do(tasks.Task)

 // 特定日期/时间
 t := time.Date(2019, time.November, 10, 15, 0, 0, 0, time.Local)
 gocron.Every(1).Hour().From(&t).Do(tasks.Task)

 // 获取下一个运行时间
 _, time := gocron.NextRun()
 fmt.Println(time)

 // 删除任务
 gocron.Remove(tasks.task)

 // 清空任务
 gocron.Clear()

 // 启动所有任务
 <-gocron.Start()

 // 额外启动一个调度器，同时运行两个调度器
 gocron2 := gocron.NewScheduler()
 gocron2s.Every(3).Seconds().Do(tasks.Task)
 <-gocron2.Start()
 ```
