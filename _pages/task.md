---
title: "Task"
---

{% contentfor sidebar %}
Tasks are processes meant to execute a one-off piece of code, generally with no communication with other processes and return a result.
{% endcontentfor %}

## Tasks vs Processes

Since tasks are just processes that execute one action throughout their lifetime, one is given to wonder whether to stick with the simple `spawn` function to start a process instead of a task. However, there are some differences.
