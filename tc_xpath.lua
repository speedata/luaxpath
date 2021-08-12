module(...,package.seeall)

local xpath = require("xpath")

xpath.register("nsfoo","adder",function(ctx, args)
    local sum = 0
    for i = 1, #args do
        sum = sum + args[i](ctx)
    end
    return sum
end )

local ctx = {
    var = {
        a = 5,
        ["one-two"] = 12,
    },
    ns = {
        foo = "nsfoo"
    }
}

function eval(str)
    return xpath.parse(str)(ctx)
end


function test_simple()
    assert_equal(eval("1"),1)
    assert_equal(eval("1 + 2"),3)
    assert_equal(eval("2 * $a"),10)
    assert_equal(eval("$one-two div $a"),2.4)
    assert_equal(eval("$one-two idiv $a"),2)
    assert_equal(eval("(1,2,3)"),{1,2,3})
    assert_equal(eval("for $foo in 1 to 3 return $foo"),{1,2,3})
    assert_equal(eval("(1,2) = (2,3)"),true)
    assert_equal(eval("(1,2 (: a comment :) ,3)"),{1,2,3})
    assert_equal(eval(" 10 idiv 3 "), 3)
    assert_equal(eval(" 3 idiv -2 "), -1)
    assert_equal(eval(" -3 idiv 2 "), -1)
    assert_equal(eval(" -3 idiv -2 "), 1)
    assert_equal(eval(" 9.0 idiv 3 "), 3)
    assert_equal(eval(" -3.5 idiv 3 "), -1)
    assert_equal(eval(" 3.0 idiv 4 "), 0)
end

function test_comparison()
    assert_true(eval(" 2 > 4 or 3 > 5 or 6 > 2"))
    assert_true(eval(" 2 > 4 or 3 > 5 or 6 > 2"))
    assert_true(eval(" true() or false() "))
    assert_true(eval(" true() and true() "))
    assert_false(eval(" true() and false() "))
    assert_false(eval(" false() or false() "))
    assert_true(eval("'a' = 'a'"))
    assert_true(eval(" 'a' = 'a' and 'b' = 'b' "))
    assert_false(eval(" 6 < 4 and 7 > 5 "))
    assert_true(eval(" 2 < 4 and 7 > 5 "))
end

function test_functions()
    assert_true(eval("if ( 1 = 1 ) then true() else false()"))
    assert_false(eval("if ( 1 = 2 ) then true() else false()"))
    assert_equal(eval("count( () )"),0)
    assert_equal(eval("count( (1,2,3) )"),3)
    assert_equal(eval(" normalize-space('  foo bar baz     ') "), "foo bar baz")
    assert_equal(eval(" upper-case('äöüaou') "), "ÄÖÜAOU")
    assert_equal(eval(" max(1,2,3) "), 3)
    assert_equal(eval(" min(1,2,3) "), 1)
end

function test_parse_string(  )
    assert_equal(eval(" 'ba\"r' "),"ba\"r")
  end

