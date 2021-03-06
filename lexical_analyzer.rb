require "byebug"

class LexicalAnalyzer
	attr_accessor :source_code, :current_state, :previous_state,
								:current_index, :current_character, :buffer,
								:current_line, :current_column, :transition_table,
								:final_states_table, :symbol_table, :take_token_table,
								:token_array, :errors

	INITIAL_STATE = 's0'
	ID_STATE      = 's9'
	ERROR_STATE   = 's26'
	EOF_STATE     = 's12'

	# FUNÇÕES PÚBLICAS ----------------------------
	# CONSTRUTOR ----------------------------------
	def initialize source_code_path
		file = File.open(source_code_path)
		@source_code = file.read
		file.close

		@current_state      = INITIAL_STATE
		@previous_state     = 'nil'
		@current_index      = 0
		@current_character  = @source_code[@current_index]
		@buffer             = ''
		@current_line       = 1
		@current_column     = 1
		@transition_table   = initialize_transition_table()
		@final_states_table = initialize_final_states()
		@symbol_table       = initialize_symbol_table()
		@state_token_table  = initialize_state_token_table()
		@errors             = []
		@end_of_file_has_been_reached = false
	end

	# ---------------------------------------------
	# FUNÇÕES PRINCIPAIS --------------------------
	def next_token
		token = nil

		while token.nil? do
			token = process_current_character
		end

		token = {"token"=>"$"} if @end_of_file_has_been_reached

		@end_of_file_has_been_reached = true if @current_state == EOF_STATE

		return token
	end

	def analyse
		token = nil
		while(token = next_token) do
			puts token

			break if token['token'] == '$'
		end
	end

	# ---------------------------------------------
	# FUNÇÕES DE IMPRESSÃO ------------------------
	def print_errors
		@errors.each do |error|
			puts error
		end
	end

	def print_info
		puts '-' * 99
		puts self.to_s
		puts '-' * 99
	end

	def print_token_array
		puts '-' * 99
		puts @token_array
		puts '-' * 99
	end

	def print_symbol_table
		puts 'Symbol Table'
		@symbol_table.each do |key, value|
		  value.each do |k,v|
		    puts "Lexeme: #{key}, Token: #{v}"
		  end
		end
	end

	def to_s
		aux_string = "Current State: #{@current_state}"
		aux_string += "\nPrevious State: #{@previous_state}"
		aux_string += "\nCurrent Character: "

		if(@source_code[@current_index] == nil)
			aux_string += 'nil'
		else
			aux_string += "'#{@source_code[@current_index]}'"
		end

		aux_string += "\nBuffer: '#{@buffer}'"
		aux_string += "\nCurrent Line: #{current_line}"
		aux_string += "\nCurrent Column: #{current_column}"
		aux_string += "\nCurrent Index: #{@current_index}"
		aux_string += "\n"
	end
	# ---------------------------------------------

	# ---------------------------------------------
	# FUNÇÕES PRIVADAS ----------------------------
	private

	# FUNÇÕES DE AUXÍLIO --------------------------
	def process_current_character
		token = nil

		increment_line_number_if_needed

		key = define_current_key

		next_state = @transition_table[@current_state][key]

		if((@current_state == INITIAL_STATE) && (@current_character == nil))
			@current_state = EOF_STATE

			token = {
				'token'  => 'EOF',
				'type'   => 'EOF',
				'lexeme' => '',
				'line'   => @current_line,
				'column' => @current_column
			}

			return token
		end

		if(a_token_was_found(next_state))
			if(token = look_for_error(next_state))
				reset_dfa

				return token
			end

			token = get_token_from_state(@current_state)

			if(token['token'] != 'Comentário')
				token['line']   = @current_line
				token['column'] = @current_column - token['lexeme'].length
			end

			# Adiciona os identificadores à tabela de símbolos.
			if(@current_state == ID_STATE)
				@symbol_table[@buffer] = {'token' => token['token']} if @symbol_table[@buffer].nil?
			end
			# -----------------------------------------

			reset_dfa

			return token
		end

		update_lex(next_state)

		token
	end

	def a_token_was_found next_state
		if((next_state == nil) || (next_state == ERROR_STATE) || (next_state == EOF_STATE))
			return true
		end

		return false
	end

	def look_for_error next_state
		token = nil

		an_error_was_found = false

		# Caso não tenha transição com o caracter processado
		# e o estado atual não seja final (erro)
		if((next_state == EOF_STATE) && (!is_final_state(@current_state)))
			an_error_was_found = true

			@errors << error_message()
		elsif(next_state == nil && !is_final_state(@current_state))
			an_error_was_found = true

			@errors << error_message()
		# -------------------------------------------
		elsif(next_state == nil && is_final_state(@current_state))
			# Caso alguma letra diferente de 'e' e 'E' seja processada
			# a partir dos estados s1 e s3
			if(@current_state == 's1' || @current_state == 's3')
				if(@current_character.match(/[a-df-zA-DF-Z]/))
					an_error_was_found = true

					@errors << error_message()
				end
			# -----------------------------------------
			# Caso qualquer letra seja processada a partir
			# do estado s6 
			elsif(@current_state == 's6')
				if(@current_character.match(/[a-zA-Z]/))
					an_error_was_found = true

					@errors << error_message()
				end
			end
		end

		if(an_error_was_found)
			token = {
				'token'  => 'Erro',
				'lexeme' => @buffer,
				'type'   => 'Erro',
				'line'   => @current_line,
				'column' => @current_column
			}
			# @token_array << token
		end

		return token
	end

	def define_current_key
		if(@current_character == nil)
			return "EOF"
		end

		# Caso nenhuma das condições abaixo sejam verdadeiras
		# o próprio caracter será a chave da tabela de transição
		key = @current_character

		# Caso qualquer caracter diferente de " seja
		# lido ao processar uma Constante Literal
		if(@current_state == "s7")
			if(@current_character != "\"")
				return "ANYTHING_ELSE"
			end
		# ------------------------------------------
		# Caso qualquer caracter diferente de } seja
		# lido ao processar um Comentário
		elsif(@current_state == "s10")
			if(@current_character != "}")
				return "ANYTHING_ELSE"
			end
		# ------------------------------------------
		# Caso os caracteres e ou E sejam processados
		# no meio de um numeral
		elsif((@current_state == "s1" || @current_state == "s3") && (@current_character == 'e' || @current_character == 'E'))
			return "E"
		# ------------------------------------------
		else
			if(@current_character.match(/[a-zA-Z]/))
				key = 'L'
			elsif(@current_character.match(/[0-9]/))
				key = 'D'
			elsif(@current_character == "\s" || @current_character == "\n" || @current_character == "\t")
				key = 'BLANK'
			end
		end

		return key
	end

	def get_token_from_state state
		aux = {}	

		# Caso o conteúdo do buffer seja um id
		# que já existe na tabela de símbolos,
		# o token retornado é o que consta na tabela.
		if(@symbol_table[@buffer])
			aux['token'] = @symbol_table[@buffer]['token']

		# Caso contrário, o próprio estado do
		# DFA determina o token reconhecido
		elsif(is_final_state(state))
			aux['token'] = @state_token_table[state]['token']
			aux['type']  = @state_token_table[state]['type']
		end

		aux['lexeme'] = @buffer

		return aux
	end

	def is_final_state state
		return @final_states_table[state]
	end

	def increment_line_number_if_needed
		if(@current_character == "\n" && @current_state == INITIAL_STATE)
			@current_line   += 1
			@current_column  = 0
		end
	end

	def reset_dfa
		@current_state  = INITIAL_STATE
		@previous_state = 'nil'

		# INVALID CHARACTER CASE (@, ç, ...) ------------------
		if @buffer.length == 0
			@current_index    += 1
			@current_column   += 1
			@current_character = @source_code[@current_index]
		end
		# -----------------------------------------------------

		@buffer = ''
	end

	def update_lex next_state
		# Esta função atualiza o estado do DFA,
		# e das demais informações, como linha,
		# coluna, buffer, caracter atual...

		cc = @current_character

		if(@current_character != nil)
			if(!((@current_state == INITIAL_STATE) && 
				 ((cc == "\s") ||
				  (cc == "\n") ||
				  (cc == "\t"))))
				@buffer += @current_character
			end
		end

		@previous_state     = @current_state
		@current_state      = next_state
		@current_index     += 1
		@current_character  = @source_code[@current_index]
		@current_column    += 1
	end

	# ---------------------------------------------
	# FUNÇÕES DE INICIALIZAÇÃO --------------------
	def initialize_final_states
		return {
			"s0"  => false,
			"s1"  => true,
			"s2"  => false,
			"s3"  => true,
			"s4"  => false,
			"s5"  => false,
			"s6"  => true,
			"s7"  => false,
			"s8"  => true,
			"s9"  => true,
			"s10" => false,
			"s11" => true,
			"s12" => true,
			"s13" => true,
			"s14" => true,
			"s15" => true,
			"s16" => true,
			"s17" => true,
			"s18" => true,
			"s19" => true,
			"s20" => true,
			"s21" => true,
			"s22" => true,
			"s23" => true,
			"s24" => true,
			"s25" => true,
			"s26" => false,
			"s27" => true,
		}
	end

	def initialize_state_token_table
		# A tabela retornada por essa função indica
		# qual token é reconhecido por cada estado final

		{
			's1'  => {'token' => 'num', 'type' => 'int'},
			's3'  => {'token' => 'num', 'type' => 'real'},
			's6'  => {'token' => 'num', 'type' => 'num'},
			's8'  => {'token' => 'lit', 'type' => 'lit'},
			's9'  => {'token' => 'id'},
			's11' => {'token' => 'Comentário'},
			's12' => {'token' => 'EOF', 'type' => 'EOF'},
			's13' => {'token' => 'OPR', 'type' => '>'},
			's14' => {'token' => 'OPR', 'type' => '>='},
			's15' => {'token' => 'OPR', 'type' => '='},
			's16' => {'token' => 'OPR', 'type' => '<'},
			's17' => {'token' => 'OPR', 'type' => '<>'},
			's18' => {'token' => 'OPR', 'type' => '<='},
			's19' => {'token' => 'OPM', 'type' => '+'},
			's20' => {'token' => 'OPM', 'type' => '-'},
			's21' => {'token' => 'OPM', 'type' => '*'},
			's22' => {'token' => 'OPM', 'type' => '/'},
			's23' => {'token' => 'AB_P', 'type' => '('},
			's24' => {'token' => 'FC_P', 'type' => ')'},
			's25' => {'token' => 'PT_V', 'type' => ';'},
			's26' => {'token' => 'Erro', 'type' => 'Erro'},
			's27' => {'token' => 'RCB', 'type' => '<-'}
		}
	end

	def initialize_symbol_table
		{
			'inicio'    => {'token' => 'inicio'},
			'varinicio' => {'token' => 'varinicio'},
			'varfim'    => {'token' => 'varfim'},
			'int'       => {'token' => 'int'},
			'real'      => {'token' => 'real'},
			'lit'       => {'token' => 'lit'},
			'leia'      => {'token' => 'leia'},
			'escreva'   => {'token' => 'escreva'},
			'se'        => {'token' => 'se'},
			'entao'     => {'token' => 'entao'},
			'fimse'     => {'token' => 'fimse'},
			'fim'       => {'token' => 'fim'}
		}
	end

	def initialize_transition_table
		return {
			"s0" => {
				"D"     => "s1",
				"\""    => "s7",
				"L"     => "s9",
				"{"     => "s10",
				"EOF"   => EOF_STATE,
				">"     => "s13",
				"="     => "s15",
				"<"     => "s16",
				"+"     => "s19",
				"-"     => "s20",
				"*"     => "s21",
				"/"     => "s22",
				"("     => "s23",
				")"     => "s24",
				";"     => "s25",
				"BLANK" => INITIAL_STATE
			},
			"s1" => {
				"D"   => "s1",
				"E"   => "s4",
				"."   => "s2", 
				"EOF" => EOF_STATE
			},
			"s2" => {
				"D"   => "s3", 
				"EOF" => EOF_STATE
			},
			"s3" => {
				"D"   => "s3",
				"E"   => "s4", 
				"EOF" => EOF_STATE
			},
			"s4" => {
				"+"   => "s5",
				"-"   => "s5",
				"D"   => "s6", 
				"EOF" => EOF_STATE
			},
			"s5" => {
				"D"   => "s6", 
				"EOF" => EOF_STATE
			},
			"s6" => {
				"D"   => "s6", 
				"EOF" => EOF_STATE
			},
			"s7" => {
				"\""            => "s8",
				"ANYTHING_ELSE" => "s7", 
				"EOF"           => EOF_STATE
			},
			"s8" => { "EOF" => EOF_STATE },
			"s9" => {
				"D"   => "s9",
				"L"   => "s9",
				"_"   => "s9", 
				"EOF" => EOF_STATE
			},
			"s10" => {
				"}"             => "s11",
				"EOF"           => EOF_STATE,
				"ANYTHING_ELSE" => "s10"
			},
			"s11" => { "EOF" => EOF_STATE },
			EOF_STATE => { "EOF" => EOF_STATE},
			"s13" => {
				"="   => "s14", 
				"EOF" => EOF_STATE
			},
			"s14" => { "EOF" => EOF_STATE },
			"s15" => { "EOF" => EOF_STATE },
			"s16" => {
				">"   => "s17",
				"-"   => "s27",
				"="   => "s18", 
				"EOF" => EOF_STATE
			},
			"s17" => { "EOF" => EOF_STATE },
			"s18" => { "EOF" => EOF_STATE },
			"s19" => { "EOF" => EOF_STATE },
			"s20" => { "EOF" => EOF_STATE },
			"s21" => { "EOF" => EOF_STATE },
			"s22" => { "EOF" => EOF_STATE },
			"s23" => { "EOF" => EOF_STATE },
			"s24" => { "EOF" => EOF_STATE },
			"s25" => { "EOF" => EOF_STATE },
			"s26" => { "EOF" => EOF_STATE },
			"s27" => { "EOF" => EOF_STATE }
		}
	end

	# ---------------------------------------------
	# FUNÇÕES DE ERRO -----------------------------
	def error_message
		description = ''

		if(@current_character == nil)
			description = "unfinished lexeme '#{@buffer}'."

			return "Lexycal Error (line #{@current_line}, column #{@current_column - 1}): #{description}"
		end

		if(@current_state == INITIAL_STATE)
			description = "unexpected '#{current_character}' starting a lexeme."
		elsif(@current_state == 's2' or @current_state == 's5' or @current_state == 's6')
			description = "unexpected '#{current_character}' instead of digit."
		elsif(@current_state == 's1' || @current_state == 's3')
			description = "'#{@current_character}' is not valid for a numeral."
		elsif(@current_state == 's4')
			description = "unexpected '#{current_character}' instead of digit or sign (+,-)."
		end

		return "Lexycal Error (line #{@current_line}, column #{@current_column}): #{description}"
	end

	# ---------------------------------------------
	# ---------------------------------------------
end
