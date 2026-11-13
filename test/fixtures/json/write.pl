:- use_module(library(iso_ext)).
:- use_module(library(swi)).
:- use_module(library(http/json)).
:- use_module(library(lists)).
t(T, O) :- catch((with_output_to(codes(Cs), json_write(current_output, T, O)), R = ok), error(E, _), (Cs = [], R = err(E))), write(R), write(': '), atom_codes(A, Cs), write(A), nl, write('----'), nl.
go :- forall(c(T, O), t(T, O)).
c(json([b = [123456789012345678901234567890,json([]),a]]), [width(30), indent(3)]).
c(json([longer_key_name([])]), []).
c([@(true),json([longer_key_name = ['q"t',json([longer_key_name = 335.00,'k e y' = 123456789012345678901234567890]),[@(false),'q"t',-216130,-0.0],@(null)],longer_key_name(0.5),'k e y' = json([longer_key_name = @(true)]),'k e y' = -247.49])], [width(30), indent(3)]).
c(json([b(1.0e10),b = -756.01,longer_key_name(-0.0),b - json(['k e y' = json([key = json([key = 48593,key = 1.0e10,key = -600336,b - 'b c']),b = 'b c',longer_key_name([-0.0,@(true),763963]),b = json(['k e y' = 'Long value to make the line wider than usual','k e y' = 123456789012345678901234567890,a = 354660,'k e y' = a,'k e y' = 1.0e10]),'k e y' = @(false)]),b - 'Long value to make the line wider than usual',a([]),b - 'é',key = 'é']),b - json(['k e y' = json([b(@(true)),'k e y' = [],a(a),longer_key_name = -0.0]),a - json([]),a = json([]),a = json([longer_key_name - json([longer_key_name - 1.0e10,a = @(null),key - 123456789012345678901234567890]),key = json([])])])]), [width(0)]).
c(json([b = ['q"t',json([b = json([a(['b c',-0.0,-485.64,@(true)]),longer_key_name(-650914)]),key = name]),[@(null),1.0e10,@(true)]],key = json([])]), [width(20)]).
c(json([]), [width(40), step(4)]).
c([[-0.0,json([b = json(['k e y' = 'q"t','k e y' = '']),key = json([longer_key_name - 'tab\tx']),a = [673438],longer_key_name = '</x>']),-0.0,[[],17.86],'b c'],name,json([]),123456789012345678901234567890,-0.0,-790159], [width(10), tab(2)]).
c(-0.0, [step(1), tab(4)]).
c([f(x),'q"t',json([a = a,longer_key_name([json([a = @(false),key = 'tab\tx',longer_key_name - 0.5,longer_key_name = f(x),longer_key_name = 998212]),@(foo)]),'k e y' = a,'k e y' = 'b c',longer_key_name = json([a = #(abc),key(json([b = 0.5,'k e y' - 123456789012345678901234567890,key - 947.91])),b('b c'),key - json([]),'k e y' = 123456789012345678901234567890])]),-940402], [null(nil), true(yes)]).
c('b c', [width(40), step(4)]).
c(json([b = 'back\\s',longer_key_name([]),key = 'b c']), [step(1), tab(4)]).
c(json([key - [['',[123456789012345678901234567890],'b c',json([a(@(false))]),-123115],json([])],longer_key_name(json([longer_key_name = json([b - '</x>']),b = -0.0,longer_key_name - 'q"t'])),key - [-865565,0.5,'</x>',@(null),-0.0],key('tab\tx'),b = json([])]), [serialize_unknown(true)]).
c('nl\nx', [width(30), indent(3)]).
c(json([key - 'b c',key - json(['k e y' = json([a(561.53),'k e y' = json(['k e y' = abcdefghijklmnopqrstuvwxyz,a - [],'k e y' - 'q"t']),longer_key_name(['tab\tx',[abcdefghijklmnopqrstuvwxyz,0.5,[@(true),123456789012345678901234567890,'Long value to make the line wider than usual',@(true),'nl\nx']],a]),b('back\\s'),a(-559198)]),longer_key_name - 1.0e10])]), [serialize_unknown(true)]).
c(json([longer_key_name = [-839006,json([a('b c'),a = json([longer_key_name = 'Long value to make the line wider than usual'])]),[],['nl\nx',@(true)],['nl\nx',''],['back\\s']],a - 'b c',b = json([longer_key_name - [],longer_key_name(62.60)]),key = 837772,longer_key_name = a]), [serialize_unknown(true)]).
c('nl\nx', [serialize_unknown(true)]).
c(-0.0, [step(1), tab(4)]).
c(@(null), [width(0)]).
c('q"t', [step(1), tab(4)]).
c([a,0.5,json([])], [width(30), indent(3)]).
c(json([key = [[[#(abc),#(foo(x)),'',1.0e10,'q"t'],'b c',abcdefghijklmnopqrstuvwxyz,json([key(1.0e10),b(1.0e10),'k e y' = -0.0]),-0.0,json([])]],b = [''],'k e y' = json(['k e y' = json([a - [@(false),740977,516642,-0.0,123456789012345678901234567890],a(abcdefghijklmnopqrstuvwxyz),key('')]),longer_key_name = json([longer_key_name - json([longer_key_name - name,b([]),a(''),key(-0.0)])]),'k e y' = 514.72,longer_key_name = json([key = '</x>',a = name])]),'k e y' = json(['k e y' = 666358,key = [json([a = 1.0e10,b = '</x>','k e y' = 'b c',longer_key_name = -0.89]),1.0e10,123456789012345678901234567890,name,#(foo(x)),json([])],b = @(false),longer_key_name - abcdefghijklmnopqrstuvwxyz,a = json([a - 0.5,'k e y' = ['back\\s',123456789012345678901234567890]])]),key = -0.0]), [step(1), tab(4)]).
c([-578383,json([key = [abcdefghijklmnopqrstuvwxyz,'b c',json([a - 'nl\nx',b = 442.73,longer_key_name = @(false),longer_key_name - 1.0e10,longer_key_name = -0.0])],b = -0.0,'k e y' = 0.5,b = json([b(json([a = 123456789012345678901234567890,a = 'é'])),b(abcdefghijklmnopqrstuvwxyz),b(json([key = @(true),longer_key_name = 'Long value to make the line wider than usual','k e y' - 0.5]))]),key([json(['k e y' = #(foo(x)),key(1.0e10),a = 'é','k e y' = #(abc),key = 0.5])])]),[-565235,json([a = ['Long value to make the line wider than usual'],'k e y' = 857.52,longer_key_name = json([key(name)])]),[json([a(abcdefghijklmnopqrstuvwxyz),key = 'back\\s','k e y' = a,longer_key_name - @(null),'k e y' = 'back\\s']),[@(false),'back\\s']],[json(['k e y' = 123456789012345678901234567890]),json([key = [123456789012345678901234567890,-939707]]),json([longer_key_name('nl\nx')])]],json([a = 0.5]),json([]),json(['k e y' = [json([key - [abcdefghijklmnopqrstuvwxyz,1.0e10,0.5,'tab\tx'],'k e y' = 'nl\nx',key - [],'k e y' = f(x),longer_key_name(name)]),[1.0e10,1.0e10,'',@(false),1.0e10,@(true)],[abcdefghijklmnopqrstuvwxyz,1.0e10,'Long value to make the line wider than usual',-428419],a],key = json(['k e y' = json([])]),longer_key_name = @(false),key = @(null)])], [step(1), tab(4)]).
c([], []).
c(json([]), [serialize_unknown(true)]).
c(476.35, [width(10), tab(2)]).
c(json([longer_key_name - [1.0e10,'q"t',0.5,123456789012345678901234567890,json([a - [a,313.69],key = 'Long value to make the line wider than usual',longer_key_name - -920.91]),['Long value to make the line wider than usual',json([key - -0.0]),['Long value to make the line wider than usual',a,-0.0,abcdefghijklmnopqrstuvwxyz,313823,-0.0]]],b = json([a = 'back\\s',b(json([])),'k e y' = json([]),b = -0.0,b - 177904]),a = [json([a - json([b - @(null),longer_key_name(-392.57),'k e y' - abcdefghijklmnopqrstuvwxyz,longer_key_name(1.0e10)])]),[@(null),['é',1.0e10,-189384]],json([a = json(['k e y' = -857.35,b = @(true),b = name]),a([abcdefghijklmnopqrstuvwxyz,f(x),'</x>',@(false)]),a - '','k e y' - json([b(110.33),'k e y' = 'é','k e y' - 1.0e10]),key(json([key - -393.75,'k e y' = -635454]))]),123456789012345678901234567890,json([b = [123456789012345678901234567890,@(null),'nl\nx','','','é'],a = 1.0e10,a = [1.0e10,0.5,-892072,@(true),1.0e10],b = json([a = 'q"t',a - '</x>',a - 'back\\s'])])]]), [width(40), step(4)]).
c([json([a(json(['k e y' = 'tab\tx',a - #(foo(x)),'k e y' = 1.0e10])),key(0.5),key(json([b = json(['k e y' = 'tab\tx',a = @(true),longer_key_name = a,a - @(false),longer_key_name = 0.5]),longer_key_name = -0.0,a - [659.97,@(true),@(false),'é'],a - json([])]))]),'tab\tx',-0.0,'nl\nx',json(['k e y' = #(foo(x)),longer_key_name = json([key = json([]),longer_key_name - @(false),'k e y' = 1.0e10,key - [abcdefghijklmnopqrstuvwxyz,'tab\tx',-0.0,a,1.0e10]])])], [width(40), step(4)]).
c(-806.43, [null(nil), true(yes)]).
c(614540, [width(10), tab(2)]).
c(json([a = json([longer_key_name = -774.83,longer_key_name([@(true)])]),longer_key_name = json(['k e y' = [91771,[[940.05,a,@(false),-643958,'back\\s'],'back\\s',@(null),0.5],json(['k e y' - @(true)]),[462.90,0.5,'é','</x>']],b = abcdefghijklmnopqrstuvwxyz,key = '']),b - 0.5,key - -870.76]), [null(nil), true(yes)]).
c('é', [step(1), tab(4)]).
c('b c', [width(40), step(4)]).
c([], [width(40), step(4)]).
c(json([b = -0.0,b(123456789012345678901234567890)]), [null(nil), true(yes)]).
c('', [width(10), tab(2)]).
c(1.0e10, [serialize_unknown(true)]).
c('q"t', [step(1), tab(4)]).
c(json([]), [width(10), tab(2)]).
c([json([b = 253.58,b - 0.5]),['</x>',1.0e10,[json([]),['Long value to make the line wider than usual',0.5]],json([])],json([]),-309.61], [serialize_unknown(true)]).
c(json([a('nl\nx'),longer_key_name(json([key = [[a,-0.0,-0.0,f(x),123456789012345678901234567890],name,json([key = @(true),b = -0.0,a(@(false)),a = 123456789012345678901234567890,a(0.5)]),json([key - 74.98,b = 'Long value to make the line wider than usual'])],key = [-0.0,json([]),[123456789012345678901234567890,932788,0.5,-0.0,-521121,@(true)]],a = [json([]),792.38]])),key = 1.0e10,key(json([key = 1.0e10,key(@(null)),a = 0.5,'k e y' - 1.0e10])),b([@(null),json([longer_key_name = 'tab\tx',b = json([key - @(null),a = '</x>',b(@(true)),a(1.0e10)]),key('q"t'),b - name]),[json([longer_key_name = 'nl\nx',b - 'é','k e y' = 'tab\tx'])],'tab\tx','nl\nx','nl\nx'])]), [serialize_unknown(true)]).
c('Long value to make the line wider than usual', []).
c([json([]),json([b(994959),'k e y' - json(['k e y' = 'b c',longer_key_name([])]),b('back\\s')]),729.48], []).
c([json(['k e y' - @(false),longer_key_name = json([longer_key_name(#(abc)),key = 802382,a('back\\s')]),'k e y' = 0.5,longer_key_name('tab\tx')]),json([longer_key_name = json([longer_key_name = json(['k e y' = 'é','k e y' = 1.0e10,'k e y' - 123456789012345678901234567890,longer_key_name(-406.07)]),key = 'back\\s','k e y' = [],a(json([key = 123456789012345678901234567890]))]),'k e y' = 1.0e10]),['é','é',[json(['k e y' - 'é','k e y' - -649922,b(-283.88)]),json([b = 482124])],json([key = ['Long value to make the line wider than usual',123456789012345678901234567890],key - 'b c',b - json([])]),'',json([key - 889526,a = abcdefghijklmnopqrstuvwxyz,key(@(null)),key - [989.85],longer_key_name(json([b('back\\s'),key(-98.84),b = '</x>',a = @(false),key - 123456789012345678901234567890]))])],json(['k e y' = json([key(json([])),longer_key_name = a,longer_key_name = @(true),'k e y' = json(['k e y' - @(foo),'k e y' - @(null),a = 'nl\nx']),b = @(null)]),'k e y' = json([b = json(['k e y' = @(true),longer_key_name = f(x),key = @(false),b = 1.0e10,'k e y' - -716.27]),b = '',a = json(['k e y' - 0.5,b = 'é']),b = json(['k e y' - 'tab\tx']),key - json([b = 0.5,key(-968581)])]),a(json([a = 'back\\s',longer_key_name = 264604,longer_key_name = -0.0])),longer_key_name([name])])], [step(1), tab(4)]).
c([[abcdefghijklmnopqrstuvwxyz,[json([]),@(true),'</x>',123456789012345678901234567890],[]],json([a = 0.5,b - #(foo(x)),a(json(['k e y' - @(true),b = a,a = json(['k e y' - -0.0,a = -0.0]),key = json([b('Long value to make the line wider than usual'),a - 'Long value to make the line wider than usual']),longer_key_name - a])),a = 124.09]),702959,json(['k e y' = 'Long value to make the line wider than usual','k e y' = json([key - [-0.0,354661],'k e y' = json([key = '</x>','k e y' = -788102,b - a]),'k e y' = 123456789012345678901234567890,longer_key_name - json([a - name,'k e y' = @(false),'k e y' - 0.5]),'k e y' - json([b(-558.50),b - #(abc)])]),a = json([b('</x>'),'k e y' = -0.0,longer_key_name - @(true),'k e y' = 123456789012345678901234567890]),'k e y' - []]),@(false),'tab\tx'], [serialize_unknown(true)]).
c('é', [step(1), tab(4)]).
c(json([a(json([a - [[],[-0.0,0.5,@(null),a],0.5,['é'],['</x>',[abcdefghijklmnopqrstuvwxyz,'b c','</x>','</x>',-105676],@(null)],json([longer_key_name = 'nl\nx',b(1.0e10),longer_key_name - 'q"t'])]])),b - 123456789012345678901234567890,a - json([longer_key_name = [['nl\nx',0.5,'tab\tx','',f(x)],json([a(@(true)),b = [-86.96],key = 'é']),['back\\s',@(true)],json([key - -344.59,'k e y' = 'tab\tx',key = #(abc),key('nl\nx'),longer_key_name('tab\tx')]),0.5]]),key = [],b - json([longer_key_name = a])]), [width(40), step(4)]).
c([json([]),json([])], [width(10), tab(2)]).
c('q"t', [width(10), tab(2)]).
c('nl\nx', [width(0)]).
c(-780687, [width(10), tab(2)]).
c(-993.32, [width(10), tab(2)]).
c(json([key - json([b - abcdefghijklmnopqrstuvwxyz])]), [width(40), step(4)]).
c('tab\tx', [serialize_unknown(true)]).
c(json([key(#(abc)),b(json([longer_key_name - #(foo(x))])),'k e y' - -259575,b = json([b(@(null)),b(json(['k e y' = 'Long value to make the line wider than usual'])),b(json([b(json([a - 'q"t',a = 1.0e10,a = [0.5,'',69.98,-496.50,'back\\s']])),a = 0.5,b(0.5),b([-0.0,[]])])),longer_key_name = [],a - name]),a = [json([longer_key_name = json([b = -0.0,key = 1.0e10]),key = [895.74,0.5,'Long value to make the line wider than usual','é'],key = 'é','k e y' = name,key = json([b - '','k e y' = [@(true),1.0e10,123456789012345678901234567890,1.0e10,[abcdefghijklmnopqrstuvwxyz],1.0e10],a(f(x)),'k e y' = 0.5])]),[json([b - 'back\\s']),'tab\tx',[-0.0,@(null),'</x>'],['nl\nx',a,abcdefghijklmnopqrstuvwxyz,[351696,667.12,123456789012345678901234567890]],json([longer_key_name = 0.5,'k e y' = 123456789012345678901234567890]),'tab\tx'],'Long value to make the line wider than usual']]), [width(30), indent(3)]).
c([0.5,json([])], [width(40), step(4)]).
c([['q"t',name,json([]),616680]], [width(30), indent(3)]).
c('Long value to make the line wider than usual', [width(10), tab(2)]).
c(json([]), []).
c(['tab\tx',json(['k e y' - -0.0,'k e y' - -0.0,longer_key_name - [0.5,551.57,'back\\s',json([]),'q"t'],key = @(false),longer_key_name = json([b - @(false),longer_key_name - json([longer_key_name - 'q"t',a = '</x>',b - 0.5,b = name,a('nl\nx')]),'k e y' - 123456789012345678901234567890])])], [width(30), indent(3)]).
c(-0.0, [width(30), indent(3)]).
c(json([]), [null(nil), true(yes)]).
c('q"t', [serialize_unknown(true)]).
c('</x>', [serialize_unknown(true)]).
c(123456789012345678901234567890, [null(nil), true(yes)]).
c([[[['é',370.69],['é'],0.5,'back\\s',a],[],-22119],123456789012345678901234567890,@(null),abcdefghijklmnopqrstuvwxyz,[[],'q"t',@(true),123456789012345678901234567890]], [width(0)]).
c(name, [width(10), tab(2)]).
c(1.0e10, [serialize_unknown(true)]).
c(json([a = 'nl\nx',b = json([longer_key_name = json([longer_key_name - 'tab\tx','k e y' = json(['k e y' = 'q"t'])]),a - @(true),a = name,longer_key_name = json([key - json([longer_key_name('b c')]),'k e y' = @(true),b = json(['k e y' = 'nl\nx',b = -0.0,'k e y' = -0.0]),key = json([a = 'b c',key = @(true)]),longer_key_name = [664.62,abcdefghijklmnopqrstuvwxyz,1.0e10]]),longer_key_name = @(false)]),key = '</x>',a - [a],b = -0.0]), [width(0)]).
c(1.0e10, [null(nil), true(yes)]).
c(json([b = #(foo(x)),'k e y' = json(['k e y' = 1.0e10,a = ['</x>',json(['k e y' = -0.0,longer_key_name - 'nl\nx',a = -0.0,longer_key_name('</x>')])]]),'k e y' = json([key - json([]),a([[692.57,'b c','é',name,@(null),''],@(true)]),'k e y' = json([longer_key_name = [],longer_key_name(123456789012345678901234567890),longer_key_name(json([])),a - ['Long value to make the line wider than usual',@(false)],longer_key_name(json([key = 'Long value to make the line wider than usual',longer_key_name(-601.97),a(0.5)]))]),a = 'nl\nx'])]), [null(nil), true(yes)]).
c(json([longer_key_name = 123456789012345678901234567890,'k e y' = []]), [width(30), indent(3)]).
c(json([a = json([b(@(false)),key(json([]))])]), [width(30), indent(3)]).
c([json([longer_key_name - 'tab\tx',longer_key_name = f(x),a(json([key(json([a = abcdefghijklmnopqrstuvwxyz])),longer_key_name - json([a(123456789012345678901234567890),'k e y' = [1.0e10,f(x),755.87],longer_key_name = @(false)]),'k e y' = 'é',b(791.94),b = #(foo(x))])),'k e y' - 'nl\nx']),json([longer_key_name - a]),[[abcdefghijklmnopqrstuvwxyz,849.72,a,name,[-813138]],'q"t','tab\tx',-452967,'tab\tx','</x>'],[],name,'nl\nx'], []).
c(json([longer_key_name('q"t')]), []).
c(1.0e10, [width(40), step(4)]).
c(json(['k e y' = [name,['back\\s'],'b c',[123456789012345678901234567890]],b = [-835164,json([longer_key_name - []]),json([longer_key_name(-2.29),'k e y' - [595.82,abcdefghijklmnopqrstuvwxyz,'Long value to make the line wider than usual','nl\nx',[f(x),'b c','é',57.43,1.0e10,'nl\nx'],-581.44]]),123456789012345678901234567890,json([]),123456789012345678901234567890],longer_key_name(json([a - 'nl\nx']))]), [width(0)]).
c([[['nl\nx','',json([b(name),b('q"t')]),-0.0,json([a(#(foo(x))),'k e y' = -638.53,b = abcdefghijklmnopqrstuvwxyz])],@(null),[['nl\nx','nl\nx',768.86],a,[#(foo(x))],[abcdefghijklmnopqrstuvwxyz]],@(null),'b c',[932403,[[0.5],1.0e10,name,'back\\s','é'],'back\\s',@(true),json([b(@(true)),'k e y' = @(false),b - '</x>',b(-644728),b = abcdefghijklmnopqrstuvwxyz])]],'tab\tx',a,-714569], [null(nil), true(yes)]).
c([@(false),#(abc),json([a(json([a(json([b = 123456789012345678901234567890,'k e y' = 'tab\tx',a = 156.54])),b(123456789012345678901234567890),b = json([b = 'b c']),'k e y' = json([longer_key_name = a,longer_key_name = -0.0,longer_key_name = @(true)]),a(json([b - '',longer_key_name = -0.0,b = 'tab\tx',b - 123456789012345678901234567890,b(341660)]))])),a(json(['k e y' = json([a = a,a([a,1.0e10,-139722,'é']),'k e y' = 'back\\s',b - '</x>']),b - json([b = 123456789012345678901234567890,'k e y' = 'b c',key = a,longer_key_name(@(null))]),'k e y' = json([longer_key_name - 169.90,'k e y' = '',key([f(x),1.0e10]),key - 0.5]),key(['back\\s',1.0e10,0.5,123456789012345678901234567890,123456789012345678901234567890,name])])),a - abcdefghijklmnopqrstuvwxyz])], [step(1), tab(4)]).
c(123456789012345678901234567890, [width(0)]).
c([[-511794]], [serialize_unknown(true)]).
c(json([key = '</x>',b(json([longer_key_name - json([b = @(true),'k e y' = 903.58])])),b(json([b(json([longer_key_name(json(['k e y' = @(null),'k e y' = name,longer_key_name = 0.5]))])),b - -457.81,a(-161.04),'k e y' - json([a = [868.71,'',[a],123456789012345678901234567890],key = json([longer_key_name - 'tab\tx']),key = json([a = 123456789012345678901234567890]),longer_key_name = [123456789012345678901234567890,'back\\s',-0.0,abcdefghijklmnopqrstuvwxyz],b = json([a(abcdefghijklmnopqrstuvwxyz),longer_key_name - 'back\\s'])]),b = json([b = -313.67,longer_key_name - -0.0,b = json([key = 0.5]),longer_key_name(json([]))])])),a(-571.58),b - json([key - 0.5,longer_key_name = [json([]),json([a = f(x),b = a,b(abcdefghijklmnopqrstuvwxyz),'k e y' - -0.0]),['',0.5,'é',0.5,#(abc)],json([longer_key_name = '',a = @(null),longer_key_name - 124.68,a = -0.0,key = #(abc)])],key - a,key - [],a = 'Long value to make the line wider than usual'])]), [width(0)]).
c(495145, [width(30), indent(3)]).
c(json([b = json([key - '</x>','k e y' = json([longer_key_name - 1.0e10,b = json([key = 'back\\s',b = 'nl\nx'])]),key = 92.34,a = 'é']),'k e y' = [-880.54,json([longer_key_name - json([b = 815.36])]),[json([b = a,longer_key_name = 123456789012345678901234567890,a = -396.45,key = 'Long value to make the line wider than usual','k e y' = 817843])]]]), [step(1), tab(4)]).
c(653.99, [serialize_unknown(true)]).
c(-0.0, [width(30), indent(3)]).
c(json([key = [[[],json([a = @(true),longer_key_name = 'tab\tx','k e y' = 'back\\s',longer_key_name - 'b c',a = 0.5]),json([key(296.52),'k e y' = 'Long value to make the line wider than usual']),json([longer_key_name - 0.5,'k e y' - '</x>',a = -0.0,b(123456789012345678901234567890)]),json([b = 'nl\nx',b = 0.5,b - 784.08]),611.00],json(['k e y' = [@(null),name],'k e y' - @(false),a - a]),json([b - [667703,[],'</x>'],a - [],longer_key_name - @(null),'k e y' = json([a(-938.15),a - 'back\\s',b = @(true),key - 'Long value to make the line wider than usual','k e y' = 'q"t'])]),234711,json([longer_key_name = 'back\\s','k e y' = #(foo(x))]),[json(['k e y' = a,longer_key_name(''),'k e y' = [#(foo(x)),'Long value to make the line wider than usual',-0.0,name,184338],a - 1.0e10]),700211,json([key([[-0.0,-442523,f(x),#(foo(x)),a],@(foo),1.0e10]),longer_key_name(949307),key = 1.0e10]),json([longer_key_name = '</x>',key = 'b c',b = -42.16,longer_key_name(@(true))]),0.5]],a = json([longer_key_name([]),longer_key_name(156.03)])]), [width(10), tab(2)]).
c('back\\s', [width(30), indent(3)]).
c(json([b - [[json(['k e y' = name])],-896801,json([longer_key_name - 'b c',b = [1.0e10]]),[@(null),json([]),json([]),'back\\s',[abcdefghijklmnopqrstuvwxyz,-0.0,a],[1.0e10]]]]), [width(0)]).
c(json([key = [],key - json(['k e y' = 'nl\nx']),b(-964377)]), [width(10), tab(2)]).
c([json([longer_key_name - [json([])],key(json([a = 584929])),key - 731954,'k e y' = 123456789012345678901234567890,longer_key_name - []]),[[0.5,-297403,[f(x),599.94,123456789012345678901234567890,'q"t']],json([a = [name],a(json(['k e y' = 'back\\s',b - @(false),a = 935.66,b = 1.0e10,b('tab\tx')])),'k e y' = json([a = 'nl\nx',b = -470117,a('q"t'),longer_key_name - 859.21,key = -179165]),key(name),'k e y' = 123456789012345678901234567890]),json([])],json([b = 123456789012345678901234567890,a = 'q"t',longer_key_name = 'é',b - 443.57,longer_key_name - json([a(json([])),key([808049,-250.57,-18.79,@(true),123456789012345678901234567890]),key(@(false))])]),a,json(['k e y' = 'q"t',b = -326.03,'k e y' - json([key = json(['k e y' = 'é',longer_key_name = -0.0]),longer_key_name([name,'</x>',1.0e10,-105.49,@(true)]),a = abcdefghijklmnopqrstuvwxyz,a(['back\\s',@(false),[123456789012345678901234567890,f(x),220083]]),a = json([key = -0.0,'k e y' - 1.0e10,a = 'b c'])]),'k e y' - json([b = [-0.0],longer_key_name('back\\s'),a(0.5),longer_key_name(json([a = '</x>','k e y' = a])),longer_key_name = [a,'nl\nx','q"t','é']])]),['tab\tx',[[0.5,962077,abcdefghijklmnopqrstuvwxyz]]]], []).
c('back\\s', [width(0)]).
c('nl\nx', [width(40), step(4)]).
c('nl\nx', [null(nil), true(yes)]).
c(0.5, [step(1), tab(4)]).
c([json([]),'Long value to make the line wider than usual',[]], []).
c([], [null(nil), true(yes)]).
c(json([]), [serialize_unknown(true)]).
c(json([]), []).
c([[],json([longer_key_name = json([b = [],b - []]),'k e y' = json([b = json([longer_key_name - '</x>',b - #(foo(x)),a(-0.0)]),'k e y' = [a,a]]),a(1.0e10)]),-148843,json([key - [],key([@(false),[-462994,1.0e10,['',[-266887,'nl\nx'],0.5,-0.0,abcdefghijklmnopqrstuvwxyz],123456789012345678901234567890],123456789012345678901234567890,['nl\nx',-0.0,-233363]]),b = #(foo(x)),'k e y' = json([key = json([b - 1.0e10,longer_key_name('b c'),'k e y' = @(false),longer_key_name = 1.0e10,longer_key_name = -580949]),key(json([])),longer_key_name - json([b - 477.80,longer_key_name(a),'k e y' = 'nl\nx',key = [325325,abcdefghijklmnopqrstuvwxyz,'tab\tx',123456789012345678901234567890],a - 213.43]),'k e y' - json([a - -0.0])]),a([[f(x),'Long value to make the line wider than usual',@(false),name,1.0e10,-426.70],[],json(['k e y' = 'back\\s',b - 1.0e10]),-37908])]),'nl\nx',json([b - [123456789012345678901234567890]])], [step(1), tab(4)]).
c(123456789012345678901234567890, [width(40), step(4)]).
c(-130.19, [width(40), step(4)]).
c(-0.0, [width(40), step(4)]).
c(#(foo(x)), []).
c(-106809, [width(30), indent(3)]).
c([], [width(40), step(4)]).
c('nl\nx', [serialize_unknown(true)]).
c([], [width(10), tab(2)]).
c([['</x>'],@(null),['q"t',json([longer_key_name = json([a - -0.0]),key - json([longer_key_name = @(null),b([1.0e10]),longer_key_name - -0.0]),a = a])],0.5], [width(0)]).
c(abcdefghijklmnopqrstuvwxyz, []).
c([[json([longer_key_name - 'tab\tx',key = -523611,b(json([a = '</x>',a - 201.78,'k e y' = 'back\\s',b - 'b c'])),'k e y' = 1.0e10,b(92568)])]], [width(20)]).
c(107328, [width(20)]).
c(a, [step(1), tab(4)]).
c([json([a = [[@(foo)]]]),[@(foo),json([a = 123456789012345678901234567890])],[[json(['k e y' = 'Long value to make the line wider than usual',longer_key_name = -425928,'k e y' = #(abc),key = 0.5]),[-0.0,@(null),'tab\tx',-56499]],[[],'nl\nx',-862.60],json([a = json(['k e y' = 376372,longer_key_name - 'nl\nx'])])],json(['k e y' = ['nl\nx','',a,1.0e10,json(['k e y' = abcdefghijklmnopqrstuvwxyz,longer_key_name - 'back\\s',key - name])],b = -0.0,a - 'b c','k e y' = -0.0,key = json([a = [],b = json([a(0.5),longer_key_name = -0.0,'k e y' = [0.5,@(true)],a = [@(true)]]),'k e y' = [],a - [486822,'Long value to make the line wider than usual',1.0e10,1.0e10,1.0e10,'back\\s']])])], [step(1), tab(4)]).
c([json([]),-0.0], [width(0)]).
c(abcdefghijklmnopqrstuvwxyz, [width(20)]).
c(json([key = name,'k e y' = [[json([]),['é'],json([b('</x>'),key(123456789012345678901234567890)])],json(['k e y' = 123456789012345678901234567890,key = 'q"t',longer_key_name - json([longer_key_name = -760874,'k e y' = 'nl\nx',key = 0.5,'k e y' = 0.5,longer_key_name('tab\tx')]),key = 123456789012345678901234567890,key - json([a = -0.0,key = 231707,key - 112.93])]),[json(['k e y' - 123456789012345678901234567890])],'tab\tx'],a - [abcdefghijklmnopqrstuvwxyz],longer_key_name = 'back\\s',b = [json([longer_key_name = -0.0,a(json([])),key - @(true),key = [['é','b c',1.0e10,name],'Long value to make the line wider than usual','Long value to make the line wider than usual',-192074,-128590]]),json([longer_key_name = 0.5,longer_key_name - [@(false),'</x>']]),[json([longer_key_name([123456789012345678901234567890]),'k e y' = a,key(a)])],123456789012345678901234567890,-561038,@(false)]]), [width(10), tab(2)]).
c(0.5, []).
c([name,a,@(true)], [null(nil), true(yes)]).
c(938.25, [step(1), tab(4)]).
c(json([a = json([b = @(false),key = [[[@(null),a],'b c'],[-949.92,abcdefghijklmnopqrstuvwxyz,'</x>',@(false),#(abc),a],name,[123456789012345678901234567890,'</x>',0.5],json([b - 1.0e10,longer_key_name - 0.5,b = 123456789012345678901234567890]),json(['k e y' - @(false),longer_key_name = 'nl\nx'])],'k e y' = 'nl\nx',longer_key_name = json(['k e y' = -759.84,a = json([key = 'nl\nx',b = 123456789012345678901234567890]),a = '',b - 'nl\nx',longer_key_name(['é',0.5])])])]), [width(10), tab(2)]).
c(1.0e10, [serialize_unknown(true)]).
c(1.0e10, [width(0)]).
c(-942.29, [null(nil), true(yes)]).
c(0.5, []).
c([[json([a(json([key = f(x),a = 123456789012345678901234567890,b = @(foo),a = 44975])),b = -0.0,key(1.0e10),'k e y' = ['Long value to make the line wider than usual','b c','',1.0e10,@(null),'é']]),'tab\tx',0.5],[abcdefghijklmnopqrstuvwxyz,json([a = name,'k e y' = [1.0e10,'tab\tx'],longer_key_name(-0.0)]),json([]),'nl\nx',[name,[name,1.0e10,1.0e10],@(null),-0.0]],[[767824,-0.0],json(['k e y' - [name,'b c','nl\nx',0.5],b(json([b = -865505,longer_key_name('b c'),longer_key_name - [-0.0,1.0e10,name,'tab\tx'],a - 'b c',b = -388.14]))]),json([a = #(foo(x))]),json([]),json([a = [abcdefghijklmnopqrstuvwxyz,name,['q"t','q"t','</x>']],a = json([a - 'q"t',b = 'b c',key - -906740,'k e y' = @(true),a = 0.5]),'k e y' = json([key(0.5)]),key(json(['k e y' = 1.0e10,key = -424395,b = -279.28])),b = -728755])],@(false)], [width(40), step(4)]).
c(-735.61, [width(30), indent(3)]).
c(['tab\tx',-829358], [null(nil), true(yes)]).
c([json([a - 'nl\nx',a = [@(null)],b = json(['k e y' = ['Long value to make the line wider than usual',abcdefghijklmnopqrstuvwxyz],b([22598]),'k e y' = json([b - 'nl\nx',key = a,a - 123456789012345678901234567890]),b - @(false)]),'k e y' = json([longer_key_name = [193.13,1.0e10,123456789012345678901234567890,123456789012345678901234567890,158971],b = 'Long value to make the line wider than usual',a - 'q"t','k e y' - json([a - -0.0,b = 'Long value to make the line wider than usual']),a - abcdefghijklmnopqrstuvwxyz]),b = [[@(foo),-138.03,403.78,-0.0],json([b = 0.5,longer_key_name = [-0.0,447.90,-566987,1.0e10],key - '',b('back\\s'),b - '</x>']),[1.0e10,-0.0,abcdefghijklmnopqrstuvwxyz,'Long value to make the line wider than usual'],1.0e10]]),[744973],'nl\nx',json([key - 'nl\nx',longer_key_name = json([longer_key_name = 'nl\nx',longer_key_name = json([key - a]),longer_key_name - 123456789012345678901234567890,b - [abcdefghijklmnopqrstuvwxyz,0.5,123456789012345678901234567890,@(foo),'tab\tx',-0.0],longer_key_name - @(null)])])], []).
c(0.5, []).
c([], [width(20)]).
c(json([b(0.5),key = ['</x>',123456789012345678901234567890,json([longer_key_name = @(true),key - 748087,longer_key_name = ['Long value to make the line wider than usual',a]])],'k e y' = 16.81]), [serialize_unknown(true)]).
c(json(['k e y' = json([a = [json(['k e y' - 'Long value to make the line wider than usual','k e y' = name,key - 123456789012345678901234567890,a - f(x),b = '']),['b c','é',-887472,'nl\nx','back\\s',0.5],'tab\tx',123456789012345678901234567890,1.0e10,1.0e10],b(json([key = [@(false)],'k e y' - name,longer_key_name - 0.5])),'k e y' = [json([longer_key_name('tab\tx'),'k e y' = 123456789012345678901234567890,b = -0.0,key - -781386]),123456789012345678901234567890,@(null)]]),key = 'nl\nx',longer_key_name = -647340,key - 'q"t',key(-0.0)]), [step(1), tab(4)]).
c(['nl\nx'], [step(1), tab(4)]).
c([[],#(foo(x)),1.0e10], [width(20)]).
c(json([longer_key_name - @(false)]), [width(20)]).
c('back\\s', [step(1), tab(4)]).
c(json([]), [width(30), indent(3)]).
c(1.0e10, [serialize_unknown(true)]).
c([0.5], [width(30), indent(3)]).
c('', [step(1), tab(4)]).
c(json(['k e y' = name]), [null(nil), true(yes)]).
c(json([]), [width(30), indent(3)]).
c(@(null), [width(10), tab(2)]).
c(json(['k e y' = 'nl\nx',a - 123456789012345678901234567890,longer_key_name = json([]),a(369062)]), [null(nil), true(yes)]).
c(json([longer_key_name = a]), []).
c([123456789012345678901234567890], [null(nil), true(yes)]).
c(json([]), [width(20)]).
c(a, [width(40), step(4)]).
c(name, [serialize_unknown(true)]).
c([1.0e10,json([a - 'b c',b = name]),json([key - 'q"t',a([]),'k e y' - json([b([]),'k e y' - @(foo),a(json([])),b(['b c',['q"t','back\\s','Long value to make the line wider than usual',0.5,@(true),'Long value to make the line wider than usual'],@(null),[name]]),b('é')]),a([]),'k e y' = [json([a - [],b = 'b c','k e y' = -0.0,key - '</x>']),['back\\s','é'],abcdefghijklmnopqrstuvwxyz,json([key - @(foo),longer_key_name = [[],'</x>','q"t','nl\nx',#(foo(x))]]),@(foo),json([b = -297.51,b - 'nl\nx',key - 'é',a = 'tab\tx',b - a])]])], [width(10), tab(2)]).
c(name, [width(20)]).
c(abcdefghijklmnopqrstuvwxyz, [serialize_unknown(true)]).
c('q"t', [step(1), tab(4)]).
c('Long value to make the line wider than usual', [width(30), indent(3)]).
c(json([key = a]), [width(0)]).
c('b c', [width(0)]).
c(json(['k e y' = -0.0,'k e y' - abcdefghijklmnopqrstuvwxyz,longer_key_name - ['b c',['',json([]),-0.0,0.5,['q"t','',abcdefghijklmnopqrstuvwxyz,1.0e10]],json([b - 1.0e10]),[json([]),[@(null),'nl\nx']]]]), [width(10), tab(2)]).
c(json([]), []).
c(json([longer_key_name - [-0.0,['Long value to make the line wider than usual',[],'back\\s',json([longer_key_name - [123456789012345678901234567890],longer_key_name(['q"t',1.0e10,1.0e10,-0.0,-0.0]),key = 'back\\s',a = 'tab\tx',b = 'q"t']),'back\\s'],123456789012345678901234567890,[json([key - 917.46,key = 1.0e10,'k e y' - @(null)]),@(false),-608.47],'tab\tx'],'k e y' = 0.5]), [serialize_unknown(true)]).
c(json(['k e y' = '',longer_key_name = json(['k e y' = '</x>']),'k e y' = '</x>']), [null(nil), true(yes)]).
c('back\\s', [width(10), tab(2)]).
c(-0.0, [serialize_unknown(true)]).
c(f(x), [width(40), step(4)]).
c(json([]), [null(nil), true(yes)]).
c([], [width(20)]).
c(['nl\nx'], [width(40), step(4)]).
c(@(null), []).
c([[123456789012345678901234567890,-186238,[[a,'b c']],'q"t',0.5,'back\\s'],['é',1.0e10,json([key = json(['k e y' = 'é',key - -0.0]),key - 0.5,longer_key_name(json([key('é'),a - @(true),'k e y' = a,key = 'b c'])),longer_key_name = json([key = @(true),a(-860.57),a('back\\s'),'k e y' = a,b = abcdefghijklmnopqrstuvwxyz])]),[json(['k e y' = 'nl\nx','k e y' = 0.5,longer_key_name - a,a = 0.5,key = 'b c']),-973.30,[],-968.32,json([a - '</x>',key = @(true),key - @(foo),b(-146217)])]],'tab\tx',json([key - json([longer_key_name = -755.96,key - ['é',name,0.5]]),b = json([b = json(['k e y' - a,a(name)]),longer_key_name(@(true)),b(json([longer_key_name = 'nl\nx',longer_key_name = [@(true),a,'back\\s','q"t',name,-0.0],longer_key_name = -727.34,longer_key_name(#(abc))]))]),'k e y' = name,key - 353430,key = ['',[1.0e10,'tab\tx'],0.5,648496,'tab\tx']]),123456789012345678901234567890], [null(nil), true(yes)]).
c(json([longer_key_name - 'Long value to make the line wider than usual','k e y' - json([key = 660228,b = json(['k e y' - json([longer_key_name - 'b c',a - 'q"t','k e y' = -447214,longer_key_name - @(false),'k e y' - [@(null),a,1.0e10,'nl\nx']]),longer_key_name = json(['k e y' = 'Long value to make the line wider than usual','k e y' - [@(false),name,0.5,-575612],a - 123456789012345678901234567890,longer_key_name = abcdefghijklmnopqrstuvwxyz]),'k e y' - json([longer_key_name = -0.0,b - -454376]),b - 'Long value to make the line wider than usual'])]),longer_key_name = 123456789012345678901234567890,a = [123456789012345678901234567890,-825171,[],['',@(false),'</x>',-369840]],a - []]), [width(40), step(4)]).
c([], []).
c(json([b = json([key - '</x>',b = json([b(@(true))]),b = json([]),longer_key_name - json([a = json([a = 0.5,b - '</x>',b = @(false)]),a - -133732,b = json([b(@(true)),key = 'q"t',longer_key_name = @(null),'k e y' = abcdefghijklmnopqrstuvwxyz]),a(['',123456789012345678901234567890,283201,'tab\tx','</x>',1.0e10]),key(-158.06)])]),b - 0.5,b([name,'back\\s',json([longer_key_name(@(foo)),b = ['q"t'],longer_key_name(123456789012345678901234567890),'k e y' = ['',name,-0.0,'','nl\nx',name],a(json([a(1.0e10),b(123456789012345678901234567890)]))]),[name],json([longer_key_name([]),longer_key_name = -340.88,longer_key_name([-40.26,0.5,'</x>','tab\tx']),b = ['</x>',-0.0]])]),'k e y' - [json([b = json([b - 123456789012345678901234567890]),'k e y' - abcdefghijklmnopqrstuvwxyz]),230.18,'b c',json([]),json(['k e y' - 791315,'k e y' = [abcdefghijklmnopqrstuvwxyz,675.75,['q"t',520950,-984415,[a,'nl\nx']]],longer_key_name = [a,'q"t',-0.0],b = ['tab\tx',-0.0,'b c','nl\nx',0.5],'k e y' = json(['k e y' = abcdefghijklmnopqrstuvwxyz,longer_key_name - '','k e y' = ''])])]]), [width(0)]).
c([], [width(20)]).
c([[-0.0,json([key(0.5),longer_key_name = []]),json(['k e y' = a,key(json([b([-563.67]),key - 'tab\tx',longer_key_name = 123456789012345678901234567890])),'k e y' = json([]),a = json([longer_key_name('tab\tx'),b - 123456789012345678901234567890,b('tab\tx')])]),[76715,'Long value to make the line wider than usual',json([key(-36.96),b('é')])],json([longer_key_name(json([a(0.5)])),longer_key_name('nl\nx'),a = -0.0,b - [0.5,0.5,'q"t','Long value to make the line wider than usual',123456789012345678901234567890,'nl\nx']]),json([a = [123456789012345678901234567890,'</x>','Long value to make the line wider than usual','Long value to make the line wider than usual'],longer_key_name('</x>'),longer_key_name = 'tab\tx'])],json([]),json([a = @(true),a = [json([a('é'),'k e y' = 'b c','k e y' = 'é',key - 'Long value to make the line wider than usual']),'',0.5,['q"t',611.26,[@(false),'','b c','é',123456789012345678901234567890]]],'k e y' = json([a - -176547,key = -0.0,b = 123456789012345678901234567890])]),json([a = abcdefghijklmnopqrstuvwxyz,b(json([key = name,'k e y' = @(foo),a([abcdefghijklmnopqrstuvwxyz,-239.22,'tab\tx','nl\nx','nl\nx',abcdefghijklmnopqrstuvwxyz]),a = ['Long value to make the line wider than usual'],'k e y' = [1.0e10,-734.75,abcdefghijklmnopqrstuvwxyz,'q"t',-0.0,@(false)]])),b - -0.0])], [width(40), step(4)]).
c(name, []).
c(json([b - @(null)]), [width(20)]).
c([0.5,abcdefghijklmnopqrstuvwxyz,@(true)], [width(40), step(4)]).
c(json([a = @(foo),b = -0.0]), [width(40), step(4)]).
c(1.0e10, [width(20)]).
c('Long value to make the line wider than usual', [null(nil), true(yes)]).
c(-546250, [width(10), tab(2)]).
c(123456789012345678901234567890, [serialize_unknown(true)]).
c(json([key = json([key = json([]),b(['nl\nx',@(true)]),b = json([key([1.0e10,'é',-525.13,615377,0.5]),longer_key_name(name),longer_key_name = [a,818.05,123456789012345678901234567890,'Long value to make the line wider than usual',-483323]]),key - ['back\\s',[123456789012345678901234567890,626.03,a,'Long value to make the line wider than usual'],'q"t',json(['k e y' = @(null),longer_key_name = 123456789012345678901234567890])],key - [508.78,'b c','back\\s',json([b = 'back\\s',a = 'é',b(-0.0)])]]),'k e y' = json([b - '</x>',b - -542172,'k e y' - 'é',a = json(['k e y' = 233686,a - []])])]), [width(30), indent(3)]).
c([], []).
c(json([key = json([b = json([longer_key_name(json(['k e y' = 123456789012345678901234567890,key = 0.5,b - name,a - 332.31,key(0.5)])),b = 'tab\tx',longer_key_name - 'q"t']),longer_key_name(123456789012345678901234567890)])]), [width(20)]).
c(json([b = 703.94,longer_key_name(693454),key = 0.5]), [width(0)]).
c(json([a = name,longer_key_name = -18.70,key = json(['k e y' - [abcdefghijklmnopqrstuvwxyz],b = 0.5,key('b c'),a = 914.46]),a = [[],['b c',json(['k e y' = 842.11,b - 123456789012345678901234567890,key - #(abc)]),json([key = @(true),'k e y' = -953.27,a - [[123456789012345678901234567890]]])],@(true),[],@(false)]]), [width(30), indent(3)]).
c([name,json([a = ['</x>',0.5,json([b - -264.10,b = @(false),a([@(true),-0.0,[abcdefghijklmnopqrstuvwxyz,'q"t','nl\nx',@(false),[552.14,'',0.5],abcdefghijklmnopqrstuvwxyz],407.60,@(true)]),longer_key_name = 'Long value to make the line wider than usual']),'</x>',json(['k e y' = 'b c',a = -20660])],longer_key_name - @(foo),longer_key_name = 123456789012345678901234567890,longer_key_name - [json([b = 'tab\tx',longer_key_name(#(foo(x))),key = 'q"t',key = 0.5,b - 'q"t'])]]),'é',[[123456789012345678901234567890,@(true)]],['',0.5,['back\\s',json([key = 1.0e10]),['tab\tx']],['back\\s',[1.0e10,'','Long value to make the line wider than usual',539292,0.5]],'back\\s']], [width(30), indent(3)]).
c('back\\s', [serialize_unknown(true)]).
c(json([longer_key_name = 123456789012345678901234567890,b = json([key = @(false),longer_key_name - [[0.5,''],-843.02],key - 'back\\s']),'k e y' - 1.0e10,'k e y' = json(['k e y' = @(true),a - '',a = 'tab\tx']),b(json([key = [json([a(@(true))])],longer_key_name([json([key - @(true),longer_key_name - abcdefghijklmnopqrstuvwxyz,longer_key_name(name),longer_key_name = -313867,longer_key_name = 'é']),'é',json([longer_key_name - 'q"t'])]),a = abcdefghijklmnopqrstuvwxyz]))]), [null(nil), true(yes)]).
c('q"t', [width(20)]).
c('b c', [width(10), tab(2)]).
c([[json([a(123456789012345678901234567890),key = 'tab\tx','k e y' - [@(false),-604.97],'k e y' - -0.0]),name,-325.61,[abcdefghijklmnopqrstuvwxyz],json([a = a,key([]),b = json(['k e y' = 123456789012345678901234567890,b = -350398,b - @(null),a(-0.0)])])]], [null(nil), true(yes)]).
c([json(['k e y' - 1.0e10])], [width(0)]).
c(json([]), [serialize_unknown(true)]).
c([[-0.0,[[],[486.45,abcdefghijklmnopqrstuvwxyz,1.0e10,''],'back\\s',['nl\nx',0.5,f(x),'back\\s',1.0e10,''],json([])],'</x>',157.56,json([a(-0.0)])],@(null),'Long value to make the line wider than usual',json([longer_key_name - json([key = json([key = -958164]),key = ['</x>','b c',3.41,abcdefghijklmnopqrstuvwxyz],a = ['back\\s',@(false),'back\\s'],key - json([key = abcdefghijklmnopqrstuvwxyz,a - 'é']),b - json(['k e y' - @(null),a = [123456789012345678901234567890],b - 1.0e10,longer_key_name - a,'k e y' - '</x>'])]),longer_key_name - 'Long value to make the line wider than usual',b = json([longer_key_name = 181363]),'k e y' = [123456789012345678901234567890,[@(null),123456789012345678901234567890,'q"t'],@(false),'b c']])], []).
c(json([a = [1.0e10,[],'nl\nx'],a = [json([key - json([]),a - abcdefghijklmnopqrstuvwxyz,a = []]),[@(true),['é',-153.54,850.73,-0.0,abcdefghijklmnopqrstuvwxyz,@(foo)]]]]), [width(20)]).
c('é', [step(1), tab(4)]).
c('é', [width(20)]).
c(a, [null(nil), true(yes)]).
c(@(true), [width(0)]).
c(json([a - [abcdefghijklmnopqrstuvwxyz,0.5,[json([key = abcdefghijklmnopqrstuvwxyz,longer_key_name(316323)]),[-0.0,#(abc)],641.64,['b c','q"t',a,a,-427.16]],json([longer_key_name - 0.5])],b = -0.0,a = json([a - '',b - 'back\\s',b = '</x>',b = 0.5])]), [null(nil), true(yes)]).
c('b c', []).
c([-0.0,'tab\tx',123456789012345678901234567890], []).
c(json(['k e y' = json([])]), []).
c(['Long value to make the line wider than usual','b c',json([b = -0.0])], [width(10), tab(2)]).
c(json([b(json([])),b - '</x>']), [width(40), step(4)]).
c('tab\tx', [null(nil), true(yes)]).
c(123456789012345678901234567890, [width(30), indent(3)]).
c(@(false), []).
c(401.66, [serialize_unknown(true)]).
c(123456789012345678901234567890, [step(1), tab(4)]).
c([94.07,json([key = json(['k e y' - [],'k e y' = '','k e y' - 'Long value to make the line wider than usual'])]),abcdefghijklmnopqrstuvwxyz,['q"t',[],'é',[json([b = name,longer_key_name = '</x>',key = 708.47,b('é')]),123456789012345678901234567890,json([key - 662.80])],1.0e10,name],-0.0,@(false)], [width(20)]).
c(@(null), [null(nil), true(yes)]).
c(json([]), [width(0)]).
c(json([longer_key_name = @(false)]), [step(1), tab(4)]).
c([json([longer_key_name('Long value to make the line wider than usual'),b - [name,[[#(foo(x)),''],0.5,'back\\s',988096],[],json([key - 123456789012345678901234567890,'k e y' - 1.0e10,'k e y' = 0.5,key = 0.5,key = '</x>']),json([])],a - [],'k e y' - 'é','k e y' = -0.0]),json([key - [[123456789012345678901234567890,'é',@(false),'q"t'],json([a = '</x>']),json([]),'</x>',['tab\tx','Long value to make the line wider than usual']],key = 123456789012345678901234567890,'k e y' = 0.5,b([])]),json(['k e y' = json(['k e y' = json([key(@(null)),b = 1.0e10,b('</x>'),key = [@(false),'',0.5,-0.0]]),a(json([key - 0.5,longer_key_name = #(abc),'k e y' = f(x),key - abcdefghijklmnopqrstuvwxyz])),b(501.69)]),a - json([longer_key_name = ['',0.5,123456789012345678901234567890,-714047],b = json([a = -552286,b = 'tab\tx','k e y' = 'tab\tx']),a = '',a(@(true)),key = '']),longer_key_name - 37.99,a(json([a([@(foo),@(false),#(abc)]),'k e y' - 'back\\s','k e y' = abcdefghijklmnopqrstuvwxyz,a('q"t')])),b = 1.0e10]),[],-530.58,@(false)], [width(0)]).
c(-0.0, [width(30), indent(3)]).
c(123456789012345678901234567890, [width(0)]).
c([[json([longer_key_name(1.0e10),key = 123456789012345678901234567890,'k e y' = 0.5,'k e y' = json([key - [-0.0,0.5,142673],key('é'),'k e y' = 123456789012345678901234567890]),'k e y' = []]),json([longer_key_name = 123456789012345678901234567890]),'q"t',-93364],'q"t',-0.0,json(['k e y' - a,longer_key_name = 586932,key = 1.0e10]),'é'], [width(20)]).
c(json([longer_key_name = 'tab\tx',longer_key_name - json([key = 1.0e10,'k e y' = #(foo(x)),b - [@(false),['</x>',123456789012345678901234567890,['nl\nx'],123456789012345678901234567890,@(false),-0.0],[123456789012345678901234567890],@(false),'nl\nx',['q"t']]]),key - 288469,a = json(['k e y' = -0.0,a = json(['k e y' = json(['k e y' = -304109,a = @(foo),key - abcdefghijklmnopqrstuvwxyz,a = 'nl\nx',a - 'tab\tx']),longer_key_name = 'q"t']),longer_key_name - json([longer_key_name = json([])])])]), [width(20)]).
c(123456789012345678901234567890, [width(10), tab(2)]).
c(json([longer_key_name - -656.26,key - json([]),'k e y' = json([b = json([a - json([key = a]),b = [0.5,123456789012345678901234567890,-0.0,'tab\tx']]),'k e y' = 0.5,'k e y' = 123456789012345678901234567890,a(''),'k e y' = @(false)]),a([436.33,123456789012345678901234567890,@(false)])]), [serialize_unknown(true)]).
c('é', [width(20)]).
c('q"t', [null(nil), true(yes)]).
c([-721.28,json([longer_key_name = 1.0e10]),['',-0.0,[-0.0,['</x>',['é',540.51,1.0e10,-813.93,1.0e10,475173]],['back\\s','','',-565632],a,['b c',123456789012345678901234567890,@(false)]],[[@(true),1.0e10],1.0e10,@(false),json([longer_key_name = a,'k e y' = @(null)]),'Long value to make the line wider than usual']],json([b(1.0e10),longer_key_name = name]),json([]),['Long value to make the line wider than usual',123456789012345678901234567890,123456789012345678901234567890,@(true)]], [width(30), indent(3)]).
c('</x>', [null(nil), true(yes)]).
c(json([a - json(['k e y' = [json([longer_key_name(#(foo(x))),a(-0.0)]),'</x>',1.0e10,[@(false),a,'</x>',-0.0,'b c',82457],[f(x),'b c','Long value to make the line wider than usual',1.0e10,@(null)],610579],key = abcdefghijklmnopqrstuvwxyz,a(json([b([f(x)]),a([1.0e10,0.5,'é',name,@(true)])])),'k e y' = [[0.5,@(true),556819],951975,a,[0.5,@(null),'b c','b c','Long value to make the line wider than usual',#(abc)],[name,123456789012345678901234567890,@(false),123456789012345678901234567890,'Long value to make the line wider than usual','nl\nx']],'k e y' = a]),'k e y' - @(false)]), [step(1), tab(4)]).
c(@(true), [width(40), step(4)]).
c(f(x), [serialize_unknown(true)]).
c([json([a = json([b - [['é',#(foo(x))],'b c','é',371034,'q"t'],longer_key_name = 'back\\s',a - 1.0e10,key(json([key = 1.0e10,key = -788.97,b - 'nl\nx']))]),key = [json(['k e y' = 123456789012345678901234567890,a = -55.13,b - 'back\\s',a = name,a = @(false)]),0.5,-0.0,'back\\s',[]],a - [[1.0e10,-0.0,-0.0,-856.69,1.0e10,100994],'nl\nx',[]]]),json([key([@(true),a]),'k e y' = 'q"t',b = 'q"t']),1.0e10,json([])], [width(0)]).
c(895518, []).
c(@(foo), [width(20)]).
c('é', [width(0)]).
c(json([b = json([longer_key_name = 'é',b = 'q"t',longer_key_name = @(false),'k e y' = -0.0]),a - [],a = 123456789012345678901234567890,a - abcdefghijklmnopqrstuvwxyz]), [width(40), step(4)]).
c('tab\tx', [null(nil), true(yes)]).
c([[[json([longer_key_name = ['Long value to make the line wider than usual',206.25,123456789012345678901234567890,784178],'k e y' - '','k e y' = @(null)]),[@(true),'back\\s']],[719573,123456789012345678901234567890,json([longer_key_name('Long value to make the line wider than usual'),key('é')]),json([key = 'Long value to make the line wider than usual',key = -306591,a = -0.0,longer_key_name = 245662,key(1.0e10)])],a,json([key - 'b c','k e y' = 1.0e10,a([]),key - json([longer_key_name('é'),longer_key_name('back\\s')]),key - json([longer_key_name = @(foo),longer_key_name - 1.0e10,longer_key_name(name),key - '</x>'])]),name],-782.59,abcdefghijklmnopqrstuvwxyz,[json([longer_key_name - 1.0e10,'k e y' - 1.0e10,'k e y' = [-200110,504.52,0.5,@(null)],a = json([key = -0.0,b(@(null))]),b = -0.0])],@(false)], [width(10), tab(2)]).
c([[name],['nl\nx',[json([]),-994.73],abcdefghijklmnopqrstuvwxyz,[json([a = 'é',longer_key_name(f(x))]),1.0e10,abcdefghijklmnopqrstuvwxyz,-806.84]],json(['k e y' = -468.66,b - -0.0]),-634593], [width(40), step(4)]).
c(['é',[0.5,json([longer_key_name('Long value to make the line wider than usual'),a = #(foo(x)),longer_key_name(json([b = abcdefghijklmnopqrstuvwxyz,'k e y' = name,key = -985.04,'k e y' - 'é'])),longer_key_name(json([key = -23705,longer_key_name = 'b c']))]),json([b = 'Long value to make the line wider than usual',a - a,a = @(foo),a - -0.0,'k e y' = 328.10])],@(false),@(true),[[]]], [serialize_unknown(true)]).
c('tab\tx', [width(40), step(4)]).
c('back\\s', [step(1), tab(4)]).
c([], []).
c(name, [serialize_unknown(true)]).
c(-0.0, [width(20)]).
c(0.5, [width(30), indent(3)]).
c(json([key = [974371,json([key - json([longer_key_name - -0.0,longer_key_name('</x>')])]),['nl\nx',f(x)]]]), [width(0)]).
c('é', []).
c(json([b = json([key = -0.0,a = -186.70,'k e y' = json([a - ['Long value to make the line wider than usual'],a(json([longer_key_name - 0.5,key - 1.0e10,longer_key_name = 'é']))]),'k e y' = -0.0]),b - json([a = json(['k e y' - [554587,0.5],b(@(foo))]),a([json(['k e y' - -163.19,'k e y' = 612.96,'k e y' = 0.5])]),b(@(true))])]), [width(10), tab(2)]).
c(json([]), [width(40), step(4)]).
c(294010, [null(nil), true(yes)]).
c('q"t', [width(40), step(4)]).
c(1.0e10, [width(0)]).
c(json([longer_key_name - 'nl\nx',a([json([key('b c'),key = json([]),b = -843.55]),@(null),0.5])]), [width(10), tab(2)]).
c(json([b = abcdefghijklmnopqrstuvwxyz]), [step(1), tab(4)]).
c([[json([key - [830592],longer_key_name = json([b = -0.0]),b = json([a = 'q"t',a = @(null),b = 'é',longer_key_name = 123456789012345678901234567890]),key - [-308.16,-74978,a,-0.0]]),a]], []).
c(json([a = [json([key(json([b - 123456789012345678901234567890,key - @(foo),'k e y' = 0.5])),a(581.56)])],key = json(['k e y' = [],b = 123456789012345678901234567890])]), [width(0)]).
c('</x>', [step(1), tab(4)]).
c(name, []).
c(json([]), [step(1), tab(4)]).
c(name, [null(nil), true(yes)]).
c('', [width(30), indent(3)]).
c([123456789012345678901234567890], [width(0)]).
c(1.0e10, [width(40), step(4)]).
c(name, [width(20)]).
c([], [width(40), step(4)]).
c('tab\tx', [width(0)]).
c(json([]), [width(30), indent(3)]).
c([['</x>',[name,['back\\s',743.62,'tab\tx','Long value to make the line wider than usual',0.5,'Long value to make the line wider than usual'],[[-0.0,-0.0,'b c'],#(abc)],['</x>','é',736872]],766376]], [null(nil), true(yes)]).
c('</x>', [width(40), step(4)]).
c([json([longer_key_name = json([key(620.39),'k e y' = [],a - f(x),longer_key_name = json([a - 0.5,a - 'nl\nx',a(@(false))]),b - json(['k e y' = 'nl\nx','k e y' - 389.09])]),b = json([key - 'back\\s','k e y' - [@(false),@(foo),-470.93]]),b - -994112]),[json([b - [@(null),name,'back\\s',-190.78,name],'k e y' = 'Long value to make the line wider than usual']),-0.0,290.13,json(['k e y' = [abcdefghijklmnopqrstuvwxyz,737688,'',0.5,1.0e10]]),123456789012345678901234567890,'Long value to make the line wider than usual'],123456789012345678901234567890,@(null)], [width(20)]).
c(json([key - a,key - json(['k e y' = json([b = 'nl\nx']),a = json([b = json([key = 'é',a = name,a = ['b c',-0.0,'tab\tx']])]),'k e y' = -207877,key = json([b = 123456789012345678901234567890,a - 4656,key(json([key(1.0e10)]))])])]), []).
c(json([b = json([key = -514.43,'k e y' = [name,['</x>',1.0e10,0.5,'é',-261.21],['é','tab\tx']],a - -856889,b = [[-0.0,-115],json([b('</x>'),a(0.5),key = abcdefghijklmnopqrstuvwxyz,a = [name],a = '</x>']),[@(null),1.0e10,-0.0,0.5,123456789012345678901234567890],[-0.0,-0.0,'</x>',a],json([a = a])],longer_key_name = #(abc)]),longer_key_name - 'é',a = [974534,[[],[-0.0,1.0e10,1.0e10],-0.0,[abcdefghijklmnopqrstuvwxyz,'back\\s','nl\nx',456765,201.83],348.89,json([key - -0.0])],json([key = 'Long value to make the line wider than usual',b(json([longer_key_name(@(true)),b(['nl\nx','q"t']),'k e y' = 'q"t',a(@(true))])),key = json([key(@(null)),key - abcdefghijklmnopqrstuvwxyz]),longer_key_name - json([])]),a,123456789012345678901234567890],b = ['Long value to make the line wider than usual',[[-0.0,'back\\s'],json([key = 0.5,'k e y' - '</x>',key = a,a(@(null)),key = #(foo(x))])],-56.22,json(['k e y' = @(null),longer_key_name = json(['k e y' = 123456789012345678901234567890,a = a,'k e y' = 0.5,longer_key_name = @(foo)]),a(['</x>',name,@(false),@(true),'</x>',929704]),a - json([key - 123456789012345678901234567890,key = 'tab\tx'])]),abcdefghijklmnopqrstuvwxyz],key = 0.5]), [width(20)]).
c(json([]), []).
c(json([key - 'é','k e y' = 1.0e10]), [width(20)]).
c([json([longer_key_name = json([a - ['</x>',0.5],'k e y' = 'é']),a = ['back\\s',json([]),json(['k e y' = a,longer_key_name - 'Long value to make the line wider than usual',longer_key_name = '',b - 681901]),'b c',[[-937.66,123456789012345678901234567890,@(true),279.82,544.65,'Long value to make the line wider than usual'],0.5,0.5,abcdefghijklmnopqrstuvwxyz,-136.77,abcdefghijklmnopqrstuvwxyz],'tab\tx']]),@(false)], [step(1), tab(4)]).
c('', [null(nil), true(yes)]).
c(json([]), [width(0)]).
c(json([longer_key_name(json([longer_key_name = json([]),'k e y' = -0.0,a - 123456789012345678901234567890,a - 'q"t'])),a - 'nl\nx','k e y' = @(false)]), [width(40), step(4)]).
c(1.0e10, [width(40), step(4)]).
c('back\\s', []).
c([json(['k e y' = json([longer_key_name([abcdefghijklmnopqrstuvwxyz,0.5,1.0e10]),key(abcdefghijklmnopqrstuvwxyz),a - json([a(-0.0),key - @(null),b(1.0e10)]),key('b c')]),b(name)])], [serialize_unknown(true)]).
c([[json([key = 'é',a(json(['k e y' - ['b c','q"t'],'k e y' = 1.0e10,a(#(abc))])),'k e y' - 'b c',a = json([]),a - json([longer_key_name - 0.5,b = 123456789012345678901234567890,b = '</x>'])]),json([longer_key_name - '</x>','k e y' = json([longer_key_name = '</x>']),key([-0.0,@(true),1.0e10,659071,0.5,'é'])]),json(['k e y' = json([])]),[json([a = [123456789012345678901234567890,[1.0e10,abcdefghijklmnopqrstuvwxyz,@(true),'Long value to make the line wider than usual',[@(true),@(null),'',name,@(false),'</x>'],'q"t'],'tab\tx',-0.0,#(abc),@(false)],key = [],longer_key_name = 511311,b = name,a = 'q"t']),'tab\tx',a,name]],@(false)], [width(40), step(4)]).
c([[json([key = [],key(-967.77),'k e y' = json([a(297992),'k e y' = [-556157,@(true)],key = 123456789012345678901234567890])]),[],[@(null),['back\\s','tab\tx'],[-0.0],[-144566,a,a,@(false),336.04,'Long value to make the line wider than usual']],'Long value to make the line wider than usual']], []).
c([json([longer_key_name(@(true)),'k e y' = [1.0e10],'k e y' = json([longer_key_name - ['b c',123456789012345678901234567890,#(foo(x)),123456789012345678901234567890],a - 111.54,longer_key_name(-0.0),longer_key_name(''),b = #(foo(x))]),'k e y' - 123456789012345678901234567890,longer_key_name = name])], [step(1), tab(4)]).
c(-0.0, []).
c([0.5,[#(foo(x)),@(true),-0.0,json(['k e y' = ['b c',12248,1.0e10,@(null),1.0e10,['nl\nx']],'k e y' = [@(false),-885866],key = [-0.0,-6594,[0.5,718.47,'b c'],-0.0,@(true),'back\\s']])],json([a = [json([]),json(['k e y' - -0.0,'k e y' = #(foo(x))]),json([b = #(abc),key - abcdefghijklmnopqrstuvwxyz,longer_key_name = 123456789012345678901234567890,b(#(abc))]),json([]),'tab\tx']])], [null(nil), true(yes)]).
c('nl\nx', [width(0)]).
c(json([b - @(true)]), []).
c(json([a = @(null),b('tab\tx'),longer_key_name = 0.5,b = json([key([]),longer_key_name - json([longer_key_name = [0.5,'é',0.5,'é'],longer_key_name('</x>'),b - -603081,longer_key_name - 0.5]),longer_key_name = json([a = 'é','k e y' = 0.5,'k e y' = -0.0,a - json([a = @(foo),a = -0.0,key - 123456789012345678901234567890]),longer_key_name = 'nl\nx']),longer_key_name([1.0e10,[123456789012345678901234567890,1.0e10],json([a = name,longer_key_name = 'Long value to make the line wider than usual']),#(abc)])]),b = json([longer_key_name - -829.39,key = 0.5,longer_key_name(json([b([123456789012345678901234567890,'é',abcdefghijklmnopqrstuvwxyz,'back\\s',@(false),314.19]),a = json([b('b c'),longer_key_name(-220.78),'k e y' = name]),'k e y' = json([]),b = 'tab\tx'])),a - 139140,b = 1.0e10])]), [null(nil), true(yes)]).
c(884.92, [step(1), tab(4)]).
c(json([key(@(true)),key - [0.5,abcdefghijklmnopqrstuvwxyz,0.5,123456789012345678901234567890],a = json(['k e y' - json([]),key - json(['k e y' = [a]]),a - [[],'q"t',1.0e10,'Long value to make the line wider than usual',@(null)],a = 123456789012345678901234567890,a = @(null)]),key = [#(foo(x)),-802754,f(x),'</x>']]), [null(nil), true(yes)]).
c(-0.0, [width(20)]).
c('q"t', [serialize_unknown(true)]).
c(json([key = json([]),b = json([])]), [serialize_unknown(true)]).
c([[],-312.01], [width(0)]).
c(1.0e10, [width(10), tab(2)]).
c(['q"t',1.0e10], [width(40), step(4)]).
c(json([longer_key_name(json(['k e y' = 896735,'k e y' - '</x>'])),a = @(false)]), [null(nil), true(yes)]).
c([[],-822531,json([a = [json(['k e y' = 1.0e10])],longer_key_name = json([]),longer_key_name = [@(false),json([]),[528.25,-337.36,[-289.62,350.31,a,''],name,544.48,'é']],b = abcdefghijklmnopqrstuvwxyz,'k e y' = []]),-0.0,'nl\nx'], [null(nil), true(yes)]).
c([], [width(20)]).
c('</x>', [width(10), tab(2)]).
