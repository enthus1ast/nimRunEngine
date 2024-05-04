import osproc, tables, random, chronicles, streams, times

type
  JobId* = int
  RunEngineJob* = object
    jobid: JobId ## local job id, defined by this machine
    remoteJobid*: JobId ## remote job id defined by the caller
    shellCommand: bool = true
    timeout: int = 1_000 * 60 * 5 # 5 minutes
    cmd: string ## the command that is executed
    args: seq[string] ## the arguments to the cmd, only used if `shellCommand == false`
    process: Process ## the process that is spawned (if not shell cmd??)
    started: bool = false ## if the process has started
    done: bool = false ## if the process is done
    workingDir: string = ""
    enqueTime: DateTime
    startTime: DateTime
    doneTime: DateTime
    outp*: string
    exitCode*: int
  RunEngine* = ref object
    jobsQueued: seq[RunEngineJob]
    jobs: Table[JobId, RunEngineJob]

proc genJobId(runEngine: RunEngine): JobId =
  ## generates a job id that is currently not in use
  while true:
    result = rand(0 .. int.high)
    if runEngine.jobs.hasKey(result): continue
    break

proc newRunEngine*(): RunEngine =
  randomize()
  return RunEngine()

proc addJob*(runEngine: var RunEngine, cmd: string, timeout = 10_000, remoteJobid: JobId = 0): JobId =
  ## adds a new job to the RunEngine, it does NOT run it yet.
  ## `cmd` is interpreted by the system shell
  result = runEngine.genJobId()
  var runEngineJob = RunEngineJob(
    remoteJobid: remoteJobid,
    jobid: result,
    shellCommand: true,
    timeout: timeout,
    cmd: cmd,
    enqueTime: now()
  )
  runEngine.jobsQueued.add runEngineJob

proc addJob*(runEngine: var RunEngine, cmd: string, args: seq[string], timeout = 10_000, remoteJobid: JobId = 0): JobId =
  ## adds a new job to the RunEngine, it does NOT run it yet.
  ## `cmd` is NOT interpreted by the system shell, param must be explicitly given in `args`
  result = runEngine.genJobId()
  var runEngineJob = RunEngineJob(
    remoteJobid: remoteJobid,
    jobid: result,
    shellCommand: false,
    timeout: timeout,
    cmd: cmd,
    args: args,
    enqueTime: now()
  )
  runEngine.jobsQueued.add runEngineJob


proc getExecutionTime*(job: RunEngineJob): Duration =
  return job.doneTime - job.startTime

proc getExecutionTime*(runEngine: RunEngine, jobid: JobId): Duration =
  let job = runEngine.jobs[jobid]
  return job.getExecutionTime()

proc runQueued(runEngine: var RunEngine) =
  ## actually runs the queued jobs
  for qq in runEngine.jobsQueued:
    debug "staring job"
    var job = qq
    job.startTime = now()
    job.started = true
    if qq.shellCommand:
      job.process = startProcess(
        command = qq.cmd,
        workingDir = qq.workingDir,
        options = {poEvalCommand, poDaemon, poStdErrToStdOut}
      )
    else:
      job.process = startProcess(
        command = qq.cmd,
        args = qq.args,
        workingDir = qq.workingDir,
        options = {poDaemon, poStdErrToStdOut}
      )
    runEngine.jobs[job.jobid] = job
  runEngine.jobsQueued = @[]

proc tick*(runEngine: var RunEngine): seq[JobId] =
  ## returns the job ids that are done.
  runEngine.runQueued() # test if its good if theyre combined
  for job in runEngine.jobs.mvalues:
    if not job.process.running():
      result.add job.jobid
      job.outp = job.process.outputStream().readAll()
      job.exitCode = waitForExit(job.process)
      job.doneTime = now()
      job.done = true

proc getJob*(runEngine: RunEngine, jobid: JobId): RunEngineJob {.raises: KeyError.} =
  return runEngine.jobs[jobid]

proc getJobs*(runEngine: RunEngine, jobids: seq[JobId]): seq[RunEngineJob] =
  for jobid in jobids:
    result.add runEngine.getJob(jobid)


proc removeJob*(runEngine: var RunEngine, jobid: JobId) =
  ## terminates the given job (by its jobid), and removes it from the engine
  logScope:
    jobid = jobid
  debug "remove job"
  
  # If not started yet, filter from queued jobs
  var stillQueued: seq[RunEngineJob] = @[]
  for qjob in runEngine.jobsQueued:
    if qjob.jobid != jobid:
      stillQueued.add qjob
  
  # If already running
  try:
    runEngine.jobs[jobid].process.terminate()
  except:
    debug "could not terminate"
  try:
    runEngine.jobs[jobid].process.close()
  except:
    debug "could not close handles"
  runEngine.jobs.del(jobid)

proc removeDoneJobs*(runEngine: var RunEngine): seq[JobId] =
  for job in runEngine.jobs.values:
    if job.done:
      result.add job.jobid
  for jobid in result:
    runEngine.removeJob(jobid)
      
proc clear*(runEngine: var RunEngine) =
  ## Kills all jobs, removes all jobs from queue
  runEngine.jobsQueued = @[]
  for jobId, pr in runEngine.jobs:
    try:
      pr.process.terminate()
    except:
      discard
  runEngine.jobs.clear() 


when isMainModule:
  import os
  var re = newRunEngine()

  # discard re.addJob(cmd = "ip a")
  discard re.addJob(cmd = "/usr/bin/ip", args = @["a"])

  # discard re.addJob(cmd = "ip a")
  # discard re.addJob(cmd = "ip a")
  # discard re.addJob(cmd = "ip a")
  # discard re.addJob(cmd = "asjdkfl")
  # discard re.addJob(cmd = "sleep 5; echo foo")
  # discard re.addJob(cmd = "sleep 6; echo foo2")
  # discard re.addJob(cmd = "sleep 70; echo foo3")

  while true:
    echo "."
    let doneJobs = re.tick() ## drives the engine
    ## do something with the output
    for jobid in doneJobs: 
      try:
        let js = re.getJob(jobid)
        echo "Runtime: ", js.getExecutionTime()
        echo "exitCode: ", js.exitCode
        echo js.outp
      except:
        continue
      re.clear()

    # echo re.addJob(cmd = "ip a")

    sleep(1000)
    echo re.removeDoneJobs()
