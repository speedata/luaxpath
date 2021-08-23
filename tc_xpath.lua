module(...,package.seeall)

local xpath = require("xpath")

dofile("xmltable1.lua")


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
        two = 2,
        one = 1,
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
    assert_equal(eval(" 1 to 3 "),{1,2,3})
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
    assert_true(eval("  boolean(1)"))
    assert_false(eval(" boolean(0)"))
    assert_false(eval(" boolean(false())"))
    assert_true(eval("  boolean(true())"))
    assert_true(eval("  boolean('false')"))
    assert_false(eval(" boolean('')"))
    assert_false(eval(" boolean( () )"))
end

function test_parse_string(  )
    assert_equal(eval(" 'ba\"r' "),"ba\"r")
end

function test_ifthenelse()
    assert_true(eval( " if ( 1 = 1 ) then true() else false()" ))
    assert_false(eval(" if ( 1 = 2 ) then true() else false()" ))
    assert_equal(eval(" if ( true() ) then 1 else 2"),1)
    assert_equal(eval(" if ( false() ) then 1 else 2"),2 )
    assert_equal(eval(" if ( false() ) then 'a' else 'b'"),"b")
    assert_equal(eval(" if ( true() ) then 'a' else 'b'"),"a")
end

function test_unaryexpr(  )
    assert_equal(eval(" -4 "), -4)
    assert_equal(eval(" +-+-+4 "), 4)
    assert_equal(eval(" 4 "), 4)
    assert_equal(eval(" 5 - 1 - 3 "), 1)
end

function test_paren()
    assert_equal(eval(" ( 6 + 4 )"), 10)
    assert_equal(eval(" ( 6 + 4 ) * 2"), 20)
end


function test_parse_arithmetic(  )
    assert_equal(eval(" 5"), 5)
    assert_equal(eval(" 3.4 "), 3.4)
    assert_equal(eval(" 'string' "), "string")
    assert_equal(eval(" 5 * 6"), 30)
    assert_equal(eval(" 5 mod 2 "), 1)
    assert_equal(eval(" 4 mod 2 "), 0)
    assert_equal(eval(" 9 * 4 div 6"), 6)
    assert_equal(eval(" 6 + 5"), 11)
    assert_equal(eval(" 6 - 5" ), 1)
    assert_equal(eval(" 6-5" ), 1)
    assert_equal(eval(" 6 + 5 + 3"), 14)
    assert_equal(eval(" 10 - 10 - 5 "), -5)
    assert_equal(eval(" 4 * 2 + 6"), 14)
    assert_equal(eval(" 6 + 4 * 2"), 14)
    assert_equal(eval(" 6 + 4  div 2"), 8)
    assert_equal(eval(" 3.4 * 2"  ), 6.8)
    assert_equal(eval(" $two + 2"), 4)
    assert_equal(eval(" 1 - $one"), 0)
    assert_equal(eval("3.4 * $two"), 6.8)
    assert_equal(eval(" $two * 3.4"), 6.8)
end

function test_comparison(  )
    assert_true(eval(" 3 < 6 " ))
    assert_false(eval(" not( 3 < 6 )" ))
    assert_true(eval(" 6 > 3 " ))
    assert_true(eval(" 3 <= 3 " ))
    assert_true(eval(" 3 = 3 " ))
    assert_true(eval(" 4 != 3 " ))
    assert_false(eval( " $two > 3 "))
    assert_true(eval( " $one = 1 "))
end

function test_string()
    assert_equal(eval("'aäßc'" ),'aäßc')
    assert_equal(eval('"aäßc"' ),'aäßc')
    assert_equal(eval("  'aäßc'  " ),'aäßc')
end

function test_multiple()
    assert_equal(eval("3 , 3" ),{3,3})
    assert_equal(eval("(3 , 3)" ),{3,3})
end

function test_num()
    assert_equal(eval(" -3.2 " ),-3.2)
    assert_equal(eval(" -3" ),-3)
end

function test_xmltable1()
    ctx.nn = xpath.NodeNavigator:new(xmldoctable1)
    assert_equal(eval("count( / root / * ) "),3)
    assert_equal(eval("count( / root / @ * ) "),4)
    assert_true(eval(" /root/@one < 2 and /root/@one >= 1 " ))
    assert_false(eval(" /root/@one > 2 and /root/@one <= 1 " ))
end
