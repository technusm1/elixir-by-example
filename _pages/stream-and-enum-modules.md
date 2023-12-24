---
title: "Stream and Enum modules"
---
Let's look at some dictionary definitions first:
> - **Stream**:  An amount of something or a number of things coming in a continuous flow. ***For example***: a constant stream of enquiries; this new service has created a new stream of revenue for the company.
> 
> - **Enumerate**: Mention a number of things one by one. More formally, it can mean: "establish the number of". ***For example***: 6,079 residents were enumerated in 241 establishments.

Elixir provides `Stream` and `Enum` modules out of the box for working with collections, i.e. it consists of 0 or more items. Collections can be enumerated, i.e. we can ask it to give us all the items contained within it. So, there are 2 possibilities:

1. **Ordinary collections**: We can think of them as a bag containing a bunch of items. The items can be organized according to a specific logic, for e.g. they can be stored in a sorted order, or they can be stored in key-value pairs (for example: in Maps) or they may be completely unorganized. An ordinary collection generally occupies memory-space in proportion to the number of items contained within it.

2. **Streams**: Elixir documentation defines Streams as "composable, lazy enumerables". Lazy implies, that they won't do anything till we tell them to. So, streams generate items on demand.