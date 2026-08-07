# Firmware: What is a queue ?

- **Author:** Yash Deshpande
- **Date:** 07-08-2026
- **Model:** Claude Opus 5

## The plainest version

Your program has work for the GPU. The GPU is a separate chip that runs on its own. So you need somewhere to leave the work.

A queue is that somewhere. It's a **shared to-do list in memory**: your program writes items on one end, the GPU reads them off the other. That's it. Everything else is detail.

## One layer down

A shared list needs three parts to actually work.

The **list itself** — a block of memory holding the items, each one a small fixed-size command like "run this kernel".

A **note of how far each side has got** — you record where you last wrote, the GPU records where it last read. Without this neither side knows whether there's new work or whether it's caught up.

A **bell** — after adding an item you write to a special address that pokes the GPU. Otherwise it would have to keep checking the list, which wastes power.

## Who owns it

**the list lives in your program's own memory**. Your process created it, your process writes to it, and adding an item doesn't involve the OS at all. The driver sets the queue up once at the start, and after that it's out of the way.

That's why GPU work can be submitted so cheaply. It's also why MEC has to be paranoid — the items it's reading were written by an ordinary program that could be buggy or malicious, so every address in them gets checked.

## Why MEC cares

Programs can make as many of these lists as they like — it's just memory. But the GPU can only actively watch **32 of them at a time**.

So from MEC's point of view a queue is in one of two conditions: sitting in memory being ignored, or currently being watched. Getting a list watched, and taking that away again when someone else needs a turn, is most of MEC's job.

## Who creates the Queue

Nobody single — it's a relay, and each step adds the one thing only it can.

**Your program asks.** `hipStreamCreate` eventually becomes a request for a queue. That's the whole contribution: "I want somewhere to put work."

**The user-space runtime builds the memory.** ROCr allocates the ring buffer and the little control structure that tracks read and write positions, both inside your process's own memory. At this point the queue exists as far as your program is concerned, but the GPU has never heard of it.

**The kernel driver makes it real.** This is the only step that needs privilege, and it supplies the three things user space can't invent: a doorbell address that actually reaches the GPU, an owner ID saying whose memory this queue's addresses belong to, and the MQD — the descriptor holding everything needed to run it.

**A scheduler on the GPU decides when it goes live.** There are two paths, and both are in this repo. The older one is the driver sending a `MAP_QUEUES` command through the KIQ, the special queue the driver uses to talk to the command processor. The newer one is MES receiving an `ADD_QUEUE` call. Either way the work is the same, and the function name says it plainly: `MapQsFetchMqdPrgmHqdKiq` — fetch the MQD, program the HQD.

**MEC just gets told.** By the time MEC is involved, a `QueueConnect` message shows up and it wires a queue that somebody else created into a slot. There is no create-queue path in MEC at all. Same at the other end: teardown is `UNMAP_QUEUES` or `REMOVE_QUEUE`, again from the scheduler, not from MEC.

So the layered answer: **your program asks, the runtime allocates, the driver authorizes, the scheduler maps, and MEC runs.**

One caveat on sourcing — the first three steps are the standard ROCm stack and aren't in this repository, so I'm describing them from how the pieces fit rather than from code here. The last three I checked directly: the KIQ's `MAP_QUEUES` and `UNMAP_QUEUES` handling, MES's `process_add_queue`, and MEC's `QueueConnect`.

## Now the real names

Same four things, as the code calls them:

- the list → the **ring buffer**, described by `CP_HQD_PQ_BASE` and `CP_HQD_PQ_CONTROL`
- how far each side got → read and write positions, mirrored into a structure your program can see
- the bell → the **doorbell**
- the setup information → the **MQD**, which becomes an **HQD** when the queue gets one of the 32 slots

And two labels attached to every queue: a **VMID** saying whose memory its addresses belong to, and a flag called `kmd_queue` saying whether this list belongs to a normal program or to the driver itself.

**One line:** a queue is a to-do list your program shares with the GPU, and MEC is the thing that decides which lists are being watched right now.
