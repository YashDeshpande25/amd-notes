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

Here's the part that surprises people: **the list lives in your program's own memory**. Your process created it, your process writes to it, and adding an item doesn't involve the operating system at all. The driver sets the queue up once at the start, and after that it's out of the way.

That's why GPU work can be submitted so cheaply. It's also why MEC has to be paranoid — the items it's reading were written by an ordinary program that could be buggy or malicious, so every address in them gets checked.

## Why MEC cares

Programs can make as many of these lists as they like — it's just memory. But the GPU can only actively watch **32 of them at a time**.

So from MEC's point of view a queue is in one of two conditions: sitting in memory being ignored, or currently being watched. Getting a list watched, and taking that away again when someone else needs a turn, is most of MEC's job.

## Now the real names

Same four things, as the code calls them:

- the list → the **ring buffer**, described by `CP_HQD_PQ_BASE` and `CP_HQD_PQ_CONTROL`
- how far each side got → read and write positions, mirrored into a structure your program can see
- the bell → the **doorbell**
- the setup information → the **MQD**, which becomes an **HQD** when the queue gets one of the 32 slots

And two labels attached to every queue: a **VMID** saying whose memory its addresses belong to, and a flag called `kmd_queue` saying whether this list belongs to a normal program or to the driver itself.

**One line:** a queue is a to-do list your program shares with the GPU, and MEC is the thing that decides which lists are being watched right now.
