A module that runs shell jobs in paralel

Driven by "tick()" that can be called as often as desired


```nim
import os
var re = newRunEngine()

discard re.addJob(cmd = "ip a")
discard re.addJob(cmd = "sleep 7; echo foo3")

while true:
    echo "."

    ## drives the engine, can be called as often as desired
    let doneJobs = re.tick() 


    ## do something with the output
    for jobid in doneJobs: 
      let js = re.getJob(jobid)
      echo "Runtime: ", js.getExecutionTime()
      echo js.outp
    sleep(1000)
    echo re.removeDoneJobs()
```
