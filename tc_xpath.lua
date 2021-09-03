
local xpath = require("xpath")

dofile("xmltable1.lua")
dofile("xmltable2.lua")


xpath.register("nsfoo","adder",function(ctx, args)
    local sum = 0
    for i = 1, #args do
        sum = sum + args[i](ctx)
    end
    return sum
end )

local ctx1 = {
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

local ctx2 = {
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


local function eval1(str)
    ctx1.nn = xpath.NodeNavigator:new(xmldoctable1)
    return xpath.parse(str)(ctx1)
end

local function eval2(str)
    ctx2.nn = xpath.NodeNavigator:new(xmldoctable2)
    return xpath.parse(str)(ctx2)
end

local test = {}

function test.test_comparison()
    assert_true(eval1(" 2 > 4 or 3 > 5 or 6 > 2"))
    assert_true(eval1(" 2 > 4 or 3 > 5 or 6 > 2"))
    assert_true(eval1(" true() or false() "))
    assert_true(eval1(" true() and true() "))
    assert_false(eval1(" true() and false() "))
    assert_false(eval1(" false() or false() "))
    assert_true(eval1("'a' = 'a'"))
    assert_true(eval1(" 'a' = 'a' and 'b' = 'b' "))
    assert_false(eval1(" 6 < 4 and 7 > 5 "))
    assert_true(eval1(" 2 < 4 and 7 > 5 "))
    assert_true(eval1(" 3 < 6 " ))
    assert_false(eval1(" not( 3 < 6 )" ))
    assert_true(eval1(" 6 > 3 " ))
    assert_true(eval1(" 3 <= 3 " ))
    assert_true(eval1(" 3 = 3 " ))
    assert_true(eval1(" 4 != 3 " ))
    assert_false(eval1( " $two > 3 "))
    assert_true(eval1( " $one = 1 "))
    assert_equal(eval1(" (((3)))  "),3)
end

function test.test_functions()
    assert_true(eval1("if ( 1 = 1 ) then true() else false()"))
    assert_false(eval1("if ( 1 = 2 ) then true() else false()"))
    assert_equal(eval1(" abs( 2 )"),2)
    assert_equal(eval1(" abs( -2 )"),2)
    assert_equal(eval1(" abs( -3.7 )"),3.7)
    assert_equal(eval1(" abs( -1.0e-7 )"),1e-7)
    assert_nan(eval1(" abs( number('NaN') )") )
    assert_true(eval1("  boolean(1)"))
    assert_false(eval1(" boolean(0)"))
    assert_false(eval1(" boolean(false())"))
    assert_true(eval1("  boolean(true())"))
    assert_false(eval1(" boolean( (false()) )"))
    assert_true(eval1("  boolean( (true()) )"))
    assert_true(eval1("  boolean('false')"))
    assert_false(eval1(" boolean('')"))
    assert_false(eval1(" boolean( () )"))

    assert_equal(eval1("ceiling(1.0)"),1)
    assert_equal(eval1("ceiling(1.6)"),2)
    assert_equal(eval1("ceiling( 17 div 3)"),6)
    assert_equal(eval1("ceiling( -3 )"), -3)
    assert_equal(eval1("ceiling( -8.2e0 )"), -8.0e0)
    assert_nan(eval1("ceiling( 'xxx' )"))
    assert_equal(eval1("ceiling( -0.5e0 )"), -0)

    assert_equal(eval1("concat('a','b')"),'ab')
    assert_equal(eval1("concat('a',$two)"),'a2')
    assert_equal(eval1("concat('a',$two,$one-two)"),'a212')

    assert_equal(eval1("count( () )"),0)
    assert_equal(eval1("count( ((),2)  )"),1)
    assert_equal(eval1("count( (1,2,3) )"),3)

    assert_true(eval1(" empty( () ) "))
    assert_true(eval1(" empty( /root/doesnotexist ) "))
    assert_true(eval1(" empty( /root/@doesnotexist ) "))
    assert_false(eval1(" empty( /root/@empty ) "))

    assert_equal(eval1("floor(1.0)"),1)
    assert_equal(eval1("floor(1.6e0)"),1)
    assert_equal(eval1("floor( 17 div 3)"),5)
    assert_equal(eval1("floor( -3 )"), -3)
    assert_equal(eval1("floor( -8.2e0 )"), -9)
    assert_nan(eval1("floor( 'xxx' )"))
    assert_equal(eval1("floor( -0.5e0 )"), -1)

    assert_equal(eval1("/root/local-name()"), 'root')
    assert_equal(eval1("local-name(/root)"), 'root')
    assert_equal(eval1("/local-name()"), '')
    assert_equal(eval1("local-name(/)"), '')
    assert_equal(eval1("local-name(/root/@foo)"), 'foo')
    assert_equal(eval1("string(/*/@*[.='no'])"), 'no')
    assert_equal(eval1("local-name(/*/@*[.='no'])"), 'foo')
    assert_equal(eval1("/root/sub/3"), {3,3,3})
    assert_equal(eval1("/root/sub/last()"), {3,3,3})
    assert_equal(eval1("string(/root/sub[last()])"), 'contents sub3contents subsub 1')

    assert_equal(eval1(" max( (1,2,3) ) "), 3)
    assert_equal(eval1(" min( (1,2,3) ) "), 1)

    assert_equal(eval1("namespace-uri(/*)"),"")

    assert_equal(eval1(" normalize-space('  foo bar baz     ') "), "foo bar baz")

    assert_equal(eval1(" round(3.2) "),3)
    assert_equal(eval1(" round(7.5) "),8)
    assert_equal(eval1(" round(-7.5) "),-7)
    assert_equal(eval1(" round(-0.0e0)) "),-0)
    assert_equal(eval1(" round( 4.6e0 ) "),5)

    assert_true(eval1(" string( 'abc' ) = 'abc'"))

    assert_equal(eval1("string-join(('a', 'b', 'c'), ', ')"),"a, b, c")
    assert_equal(eval1("string-join(('A', 'B', 'C'), '')"),"ABC")
    assert_equal(eval1("string-join((), '∼') "), "")

    assert_equal(eval1("string-length('a')"),1)
    assert_equal(eval1("string-length('ä')"),1)
    assert_equal(eval1("string-length('')"),0)

    assert_equal(eval1(" upper-case('äöüaou') "), "ÄÖÜAOU")
end


function test.test_ifthenelse()
    assert_true(eval1( " if ( 1 = 1 ) then true() else false()" ))
    assert_false(eval1(" if ( 1 = 2 ) then true() else false()" ))
    assert_equal(eval1(" if ( true() ) then 1 else 2"),1)
    assert_equal(eval1(" if ( false() ) then 1 else 2"),2 )
    assert_equal(eval1(" if ( false() ) then 'a' else 'b'"),"b")
    assert_equal(eval1(" if ( true() ) then 'a' else 'b'"),"a")
end

function test.test_unaryexpr(  )
    assert_equal(eval1(" -4 "), -4)
    assert_equal(eval1(" +-+-+4 "), 4)
    assert_equal(eval1(" 5 - 1 - 3 "), 1)
end


function test.test_parse_arithmetic(  )
    assert_equal(eval1(" 4 "), 4)
    assert_equal(eval1(" -3.2 " ),-3.2)
    assert_equal(eval1(" -3" ),-3)
    assert_equal(eval1(" 5"), 5)
    assert_equal(eval1(" 3.4 "), 3.4)
    assert_equal(eval1(" 'string' "), "string")
    assert_equal(eval1(" 5 * 6"), 30)
    assert_equal(eval1(" 5 mod 2 "), 1)
    assert_equal(eval1(" 4 mod 2 "), 0)
    assert_equal(eval1(" 9 * 4 div 6"), 6)
    assert_equal(eval1(" 6 + 5"), 11)
    assert_equal(eval1(" 6 - 5" ), 1)
    assert_equal(eval1(" 6-5" ), 1)
    assert_equal(eval1(" 6 + 5 + 3"), 14)
    assert_equal(eval1(" 10 - 10 - 5 "), -5)
    assert_equal(eval1(" 4 * 2 + 6"), 14)
    assert_equal(eval1(" 6 + 4 * 2"), 14)
    assert_equal(eval1(" 6 + 4  div 2"), 8)
    assert_equal(eval1(" 3.4 * 2"  ), 6.8)
    assert_equal(eval1(" $two + 2"), 4)
    assert_equal(eval1(" 1 - $one"), 0)
    assert_equal(eval1("3.4 * $two"), 6.8)
    assert_equal(eval1(" $two * 3.4"), 6.8)
    assert_equal(eval1(" ( 6 + 4 )"), 10)
    assert_equal(eval1(" ( 6 + 4 ) * 2"), 20)
    assert_equal(eval1("2 * $a"),10)
    assert_equal(eval1("$one-two div $a"),2.4)
    assert_equal(eval1("$one-two idiv $a"),2)
    assert_equal(eval1("(1,2,3)"),{1,2,3})
    assert_equal(eval1(" 1 to 3 "),{1,2,3})
    assert_equal(eval1("for $foo in 1 to 3 return $foo"),{1,2,3})
    assert_equal(eval1("(1,2) = (2,3)"),true)
    assert_equal(eval1("(1,2 (: a comment :) ,3)"),{1,2,3})
    assert_equal(eval1(" 10 idiv 3 "), 3)
    assert_equal(eval1(" 3 idiv -2 "), -1)
    assert_equal(eval1(" -3 idiv 2 "), -1)
    assert_equal(eval1(" -3 idiv -2 "), 1)
    assert_equal(eval1(" 9.0 idiv 3 "), 3)
    assert_equal(eval1(" -3.5 idiv 3 "), -1)
    assert_equal(eval1(" 3.0 idiv 4 "), 0)
end

function test.test_string()
    assert_equal(eval1("'aäßc'" ),'aäßc')
    assert_equal(eval1('"aäßc"' ),'aäßc')
    assert_equal(eval1("  'aäßc'  " ),'aäßc')
    assert_equal(eval1(" 'ba\"r' "),"ba\"r")
end

function test.test_multiple()
    assert_equal(eval1("3 , 3" ),{3,3})
    assert_equal(eval1("(3 , 3)" ),{3,3})
    assert_true(eval1("(1,2,3)[2] = 2"))
    assert_true(eval1("( (),2 )[1] = 2"))
    assert_equal(eval1("( 1,2,(),3 )"),{1,2,3})
end

function test.test_xmltable1()
    assert_equal(eval1("count( / root / * ) "),5)
    assert_equal(eval1("count( / root / @ * ) "),4)
    assert_true(eval1(" /root/@one < 2 and /root/@one >= 1 " ))
    assert_false(eval1(" /root/@one > 2 and /root/@one <= 1 " ))
    assert_equal(eval1("count( /root/sub[position() mod 2 = 0]) "),1)
    assert_equal(eval1("count( /root/sub[position() mod 2 = 1]) "),2)
    assert_equal(eval1(" string(/root/sub[position() mod 2 = 0]/@foo) "),'bar')
    assert_equal(eval1(" count(/root/sub[3]) "),1)
    assert_equal(eval1(" count(/root/sub[4]) "),0)
    assert_equal(eval1(" count(/root[1]/sub[3]) "),1)
    assert_equal(eval1(" count(/root/sub[3][1]) "),1)
    assert_equal(eval1(" /root/sub[@foo='bar']/last()"),{2,2})
    assert_equal(eval1(" count(/root/sub[@foo='bar']/last())"),2)
    assert_equal(eval1("(/root/sub[@foo='bar']/last())[1]"),2)
    assert_true(eval1(" ( /root/@doesnotexist , 'str' )[1] = 'str'  "))
    assert_true(eval1(" ( 'str', /root/@doesnotexist  )[1] = 'str'  "))
    assert_equal(eval1(" string(/root/@one)"),"1")
end

function test.test_xmltable2()
    assert_equal(eval2("namespace-uri(/*)"),"nsfoo")
    assert_equal(eval2("/*/namespace-uri()"),"nsfoo")
end


return test