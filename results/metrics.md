# Benchmark Metrics

| Result | Model | Variant | Boot | Demo GIF | Total tok | In | Out | Reason | Cache R | Cost $ | Wall s | Iters | Tools | Error |
| --- | --- | --- | :---: | :---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| fable5 | opencode/claude-fable-5 | high | ok | ok | 100146 | 146 | 100000 | 0 | 8987164 | 16.188574 | 1924.44 | 73 | 76 |  |
| opus5 | opencode/claude-opus-5 | max | ok | ok | 193738 | 172 | 193566 | 0 | 15494577 | 17.324792249999994 | 2923.74 | 87 | 83 |  |
| gpt56-terra | openai/gpt-5.6-terra | xhigh | ok | ok | 242542 | 198969 | 20715 | 22858 | 6105088 | 0 | 1112.23 | 91 | 103 |  |
| grok45 | opencode/grok-4.5 | high | ok | ok | 249249 | 160212 | 63732 | 25305 | 27525760 | 14.617526000000005 | 1173.8 | 286 | 290 |  |
| gpt56-sol | openai/gpt-5.6-sol | xhigh | ok | ok | 257017 | 220898 | 14071 | 22048 | 8560128 | 0 | 1841.62 | 114 | 126 |  |
| deepseekv4pro | voban/deepseek-v4-pro | max | ok | ok | 391697 | 113005 | 59341 | 219351 | 77323776 | 0 | 5339.959999999999 | 330 | 329 |  |
| deepseekv4flash | voban/deepseek-v4-flash | max | ok | ok | 428143 | 119755 | 32418 | 275970 | 34019968 | 0 | 2776.7300000000005 | 127 | 132 |  |
| opus48 | opencode/claude-opus-4-8 | max | ok | ok | 449202 | 344 | 448858 | 0 | 59743514 | 53.01377700000002 | 1633.25 | 174 | 174 |  |
| kimik3 | opencode/kimi-k3 | max | ok | ok | 460548 | 299761 | 160787 | 0 | 15646827 | 8.005136100000001 | 3492.23 | 94 | 108 |  |
| qwen38 | voban/qwen3.8-max | - | ok | ok | 45596763 | 45069377 | 37680 | 489706 | 2834048 | 0 | 17456.6 | 107 | 116 |  |
| gpt55 | openai/gpt-5.5 | xhigh | ok | ok | 259551 | 214254 | 13381 | 31916 | 7028224 | 0 | 1201.0 | 106 | 109 | timeout after 1200s |

## Thinking versus doing

| Result | Reason chars | Per tool call | Tools | Edits | 1st tool s | 1st edit s | Longest silence s |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| fable5 |  |  |  |  |  |  |  |
| opus5 | 156500 | 1886 | 83 | 11 | 4.81 | 33.75 | 636.05 |
| gpt56-terra | 6811 | 66 | 103 | 17 | 5.18 | 198.21 | 162.68 |
| grok45 |  |  |  |  |  |  |  |
| gpt56-sol | 12793 | 91 | 141 | 14 | 18.92 | 27.13 | 375.93 |
| deepseekv4pro | 776823 | 2258 | 344 | 63 | 3.1 | 119.45 | 243.02 |
| deepseekv4flash | 859516 | 6511 | 132 | 17 | 3.53 | 771.01 | 3304.75 |
| opus48 |  |  |  |  |  |  |  |
| kimik3 | 412303 | 3818 | 108 | 23 | 4.76 | 919.01 | 896.94 |
| qwen38 | 1393938 | 12017 | 116 | 36 | 11.31 | 1963.95 | 2594.14 |
| gpt55 |  |  |  |  |  |  |  |
