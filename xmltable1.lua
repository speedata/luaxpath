xmldoctable1 = {
    [".__type"] = "document",
    [1] = {
        [".__name"] = "root",
        [".__type"] = "element",
        [".__local_name"] = "root",
        [".__namespace"] = "",
        [".__ns"] = {
        },
        attributes = { ["empty"] = "", ["quotationmarks"] = "\"text\"",  ["one"] = "1", ["foo"] = "no"},
        [1] = "\n    ",
        [2] = {
            [".__name"] = "sub",
            [".__type"] = "element",
            [".__local_name"] = "sub",
            [".__namespace"] = "",
            [".__ns"] = {
            },
            attributes = {["foo"] = "baz",someattr = "somevalue"},
            [1] = "123",
            },
        [3] = "\n    ",
        [4] = {
            [".__name"] = "sub",
            [".__type"] = "element",
            [".__local_name"] = "sub",
            [".__namespace"] = "",
            [".__ns"] = {
            },
            attributes = { ["foo"] = "bar"},
            [1] = "contents sub2",
        },
        [5] = "\n    ",
        [6] = {
            [".__name"] = "subx",
            [".__type"] = "element",
            [".__local_name"] = "sub",
            [".__namespace"] = "",
            [".__ns"] = {
            },
            attributes = { ["foo"] = "bar"},
            [1] = "contents sub3",
            [2] = {
                [".__name"] = "subsub",
                [".__type"] = "element",
                [".__local_name"] = "subsub",
                [".__namespace"] = "",
                [".__ns"] = {
                },
                attributes = { ["foo"] = "bar"},
                [1] = "contents subsub 1",
            },
        },
        [7] = "\n",
    },
}
