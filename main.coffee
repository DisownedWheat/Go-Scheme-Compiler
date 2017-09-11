'use strict'

nameMaps =
    '+': 'add'
    '-': 'subtract'
    '^': 'exponent'
    '<': 'lessThan'
    '>': 'greaterThan'
    ':': 'colon',

charIsWhitespace = (char) ->
    char in [' ', '\t', '\n', '\r']

charIsParen = (char) ->
    char in ['(', ')', '[', ']', '{', '}']

checkTokenName = (token) ->
    if nameMaps[token.value]?
        return nameMaps[token.value]

tokenizer = (input) ->
    current = 0

    tokens = []

    while current < input.length

        char = input[current]

        if char in ['(', ')', '[', ']', '{', '}']
            tokens.push
                type: 'paren'
                value: char

            current++
            continue

        if char in ['(', ')', '[', ']', '{', '}']
            tokens.push
                type: 'paren'
                value: char

            current++
            continue

        if charIsWhitespace char
            current++
            continue

        NUMBERS = /[0-9]/
        if NUMBERS.test char
            value = ''

            while NUMBERS.test char
                value += char
                char = input[++current]

            tokens.push {type: 'number', value}

            continue

        if char == '"'
            value = ''

            char = input[++current]

            while char != '"'
                value += char
                char = input[++current]

            char = input[++current]

            tokens.push {type: 'string', value}

            continue

        if char == '\''
            tokens.push
                type: 'quote'
                value: '\''
            current++
            continue

        value = ''
        while (not charIsWhitespace char) and (not charIsParen char)
            value += char
            char = input[++current]


        tokens.push {type: 'ident', value}

    return tokens

parser = (tokens) ->
    current = 0

    walk = ->

        token = tokens[current]

        if token.type == 'number'
            current++
            return
                type: 'NumberLiteral'
                value: token.value

        if token.type == 'string'
            current++
            return
                type: 'StringLiteral'
                value: token.value

        if token.type == 'ident'
            current++
            return
                type: 'Identifier'
                value: token.value

        if token.type == 'quote'
            current++
            return
                type: 'Quote'

        if token.type == 'paren' and token.value == '('

            token = tokens[++current]
            node =
                type: 'CallExpression'
                name: token.value
                params: []

            token = tokens[++current]

            while (
                (token.type != 'paren') or
                (token.type == 'paren' and token.value != ')')
            )
                node.params.push walk()
                token = tokens[current]

            current++
            return node

    ast =
        type: 'Program'
        body: []

    while current < tokens.length
        ast.body.push walk()

    ast

traverser = (ast, visitor) ->
    traverseArray = (array, parent) ->
        array.forEach (child) ->
            traverseNode child, parent

    traverseNode = (node, parent) ->
        methods = visitor[node.type]

        if methods? and methods.enter then methods.enter node, parent

        switch node.type
            when 'Program' then traverseArray node.body, node
            when 'CallExpression' then traverseArray node.params, node
            else break

        if methods? and methods.exit then methods.exit node, parent
    traverseNode ast, null

transformer = (ast) ->
    newAst =
        type: 'Program'
        body: []

    ast._context = newAst.body

    traverser ast,
        NumberLiteral:
            enter: (node, parent) ->
                parent._context.push
                    type: 'NumberLiteral'
                    value: node.value

        StringLiteral:
            enter: (node, parent) ->
                parent._context.push
                    type: 'StringLiteral'
                    value: node.value

        Identifier:
            enter: (node, parent) ->
                parent._context.push
                    type: 'Identifier'
                    name: node.value

        CallExpression:
            enter: (node, parent) ->
                expression =
                    type: 'CallExpression'
                    callee: {
                        type: 'Callee'
                        name: node.name
                    }
                    arguments: []

                node._context = expression.arguments

                if parent.type != 'CallExpression'
                    type: 'ExpressionStatement'
                    expression: expression

                parent._context.push expression

            exit: (node, parent) ->

                # This handles lambda/function declarations
                i = parent._context.length - 1
                n = parent._context[i]
                # If this is not the define function
                if n.callee.name != 'define' and n.callee.name != 'lambda'
                    return
                if n.arguments[0].type != 'CallExpression'
                    return
                child = n.arguments[0]
                child.type = 'Lambda'
                child.name = child.callee.name
                child.body = n.arguments.slice(1)
                n.arguments = [child]

    newAst

codeGenerator = (node) ->
    switch node.type
        when 'Program' then node.body.map(codeGenerator)
        when 'ExpressionStatement' then return codeGenerator(node.expression) + ';'
        when 'Callee' then return "\"" + node.name + "\""
        when 'Lambda'
            val = "RT.SchemeFunc{Args: []RT.SchemeInterface{#{node.arguments.map(codeGenerator).join(', ')}},"
            val += "Name: \"#{node.name}\","
            val += "Value: func(parent *RT.Env, args []RT.SchemeInterface) RT.SchemeInterface"
            val += "{var temp RT.Env;env := &temp;env.Parent = parent;env.Variables = map[string]RT.SchemeInterface{};"
            node.arguments.forEach (x, i) ->
                val += "env.Variables[\"#{x.name}\"] = args[#{i}]; "
            val += "#{node.body.slice(0, -1).map(codeGenerator)} return #{node.body.slice(-1).map(codeGenerator)}}}"
            return val
        when 'ArgList'
            return "RT.SchemeList{Value: []RT.SchemeInterface{#{node.arguments.map(codeGenerator).join(', ')}}}"
        when 'CallExpression'
            val = "RT.Call(env, env, #{codeGenerator(node.callee)},\n"
            val += "[]RT.SchemeInterface{#{node.arguments.map(codeGenerator).join(', ')}})"
            return val
        when 'Identifier'
            return "RT.SchemeSymbol{Value: \"#{node.name}\"}"
        when 'NumberLiteral'
            return "RT.SchemeNumber{Value: #{node.value},}"
        when 'StringLiteral'
            return "RT.SchemeString{Value: \"#{node.value}\",}"


value = "
  (define x 1)
  (print (+ (+ x 1) 2))
  (define (x y)
    (print y))
  (x 1)
  (define (z a b c)
    (print a b c))
  (z \"Hello\" 2 3)
  (print (= \"1\" 1))
"

toks = tokenizer value
ast = parser toks
newAst = transformer ast
code = codeGenerator newAst

console.log "package main \n
import \"github.com/DisownedWheat/Go-Scheme-Runtime\"\n\n

func main() {\n
    env := RT.MakeRootEnv()\n
    #{code.join ';'}
}"