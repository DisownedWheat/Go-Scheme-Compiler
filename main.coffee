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
                        type: 'Identifier'
                        name: node.name
                    }
                    arguments: []

                node._context = expression.arguments

                if parent.type != 'CallExpression'
                    type: 'ExpressionStatement'
                    expression: expression

                parent._context.push expression

    newAst

codeGenerator = (node) ->
    switch node.type
        when 'Program' then node.body.map(codeGenerator)
        when 'ExpressionStatement' then return codeGenerator(node.expression) + ';'
        when 'CallExpression'
            return "#{codeGenerator(node.callee)}(#{node.arguments.map(codeGenerator).join(', ')})"
        when 'Identifier' then return node.name
        when 'NumberLiteral' then return node.value
        when 'StringLiteral' then return '"' + node.value + '"'


value = "
  (define x 1)
  (define (y z)
    (+ x 1))
"

toks = tokenizer value
ast = parser toks
newAst = transformer ast
code = codeGenerator newAst

console.log "package main \n
import \"fmt\"\n\n

func main() {
    #{code.join ';'}
}"