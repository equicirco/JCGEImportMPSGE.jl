"""
JCGEImportMPSGE converts `MPSGE.jl` model objects into JCGE block RunSpecs.
"""
module JCGEImportMPSGE

using JCGEBlocks
using JCGECalibrate: LabeledMatrix
using JCGECore
using MPSGE

export import_mpsge

"""
    import_mpsge(model; name="MPSGEImport", data=nothing)

Import an `MPSGE.jl` model object into a JCGE `RunSpec`.

When `data` is provided, it is used to populate a data-rich, MCP-style
specification via `_import_mpsge_data`. Otherwise a minimal structure is built
from the MPSGE production and demand trees.
"""
function import_mpsge(model::MPSGEModel; name::String="MPSGEImport", data=nothing)
    if data !== nothing
        return _import_mpsge_data(model, data; name=name)
    end
    return _import_mpsge_minimal(model; name=name)
end

"""
    _import_mpsge_minimal(model; name)

Internal: build a minimal RunSpec using production, demand, and endowment flows.
"""
function _import_mpsge_minimal(model::MPSGEModel; name::String)
    commodity_objs = MPSGE.commodities(model)
    sector_objs = MPSGE.sectors(model)
    consumer_objs = MPSGE.consumers(model)

    commodity_labels = Dict(c => _strip_index_name(Symbol(MPSGE.name(c))) for c in commodity_objs)
    sector_labels = Dict(s => _strip_index_name(Symbol(MPSGE.name(s))) for s in sector_objs)
    consumer_labels = Dict(c => _strip_index_name(Symbol(MPSGE.name(c))) for c in consumer_objs)

    commodities = [_strip_index_name(Symbol(MPSGE.name(c))) for c in commodity_objs]
    activities = [_strip_index_name(Symbol(MPSGE.name(s))) for s in sector_objs]
    consumers = [_strip_index_name(Symbol(MPSGE.name(c))) for c in consumer_objs]

    a_out = zeros(length(commodities), length(activities))
    a_in = zeros(length(commodities), length(activities))
    alpha = zeros(length(commodities), length(consumers))
    endowment = zeros(length(commodities), length(consumers))

    commodity_index = Dict(c => i for (i, c) in enumerate(commodities))
    activity_index = Dict(a => i for (i, a) in enumerate(activities))
    consumer_index = Dict(c => i for (i, c) in enumerate(consumers))

    for prod in MPSGE.productions(model)
        s = sector_labels[MPSGE.sector(prod)]
        s_idx = activity_index[s]
        for (commodity, netputs) in MPSGE.netputs(prod)
            g = commodity_labels[commodity]
            g_idx = commodity_index[g]
            for netput in netputs
                qty = _scalar_value(MPSGE.quantity(netput))
                if MPSGE.netput_sign(netput) > 0
                    a_out[g_idx, s_idx] += qty
                else
                    a_in[g_idx, s_idx] += qty
                end
            end
        end
    end

    demand_map = Dict(MPSGE.consumer(d) => d for d in MPSGE.demands(model))
    for cons in consumer_objs
        cons_sym = consumer_labels[cons]
        cons_idx = consumer_index[cons_sym]
        demand = get(demand_map, cons, nothing)
        demand === nothing && error("Missing demand for consumer $(cons_sym)")

        for (commodity, flows) in MPSGE.final_demands(demand)
            g = commodity_labels[commodity]
            g_idx = commodity_index[g]
            for flow in flows
                alpha[g_idx, cons_idx] += _scalar_value(MPSGE.quantity(flow))
            end
        end
        for (commodity, flows) in MPSGE.endowments(demand)
            g = commodity_labels[commodity]
            g_idx = commodity_index[g]
            for flow in flows
                endowment[g_idx, cons_idx] += _scalar_value(MPSGE.quantity(flow))
            end
        end
    end

    for c_idx in 1:length(consumers)
        total = sum(alpha[:, c_idx])
        total <= 0 && error("Final demand quantities for consumer $(consumers[c_idx]) sum to zero.")
        alpha[:, c_idx] ./= total
    end

    a_out_mat = LabeledMatrix(a_out, commodities, activities)
    a_in_mat = LabeledMatrix(a_in, commodities, activities)
    alpha_mat = LabeledMatrix(alpha, commodities, consumers)
    endow_mat = LabeledMatrix(endowment, commodities, consumers)

    params = (a_out=a_out_mat, a_in=a_in_mat, alpha=alpha_mat, endowment=endow_mat, mcp=true)

    activity_to_output = Dict{Symbol,Symbol}()
    for (a_idx, a) in enumerate(activities)
        out_idx = findfirst(x -> x > 0.0, a_out[:, a_idx])
        out_idx === nothing && error("No positive output for activity $(a)")
        activity_to_output[a] = commodities[out_idx]
    end
    sets = JCGECore.Sets(commodities, activities, commodities, consumers)
    mappings = JCGECore.Mappings(activity_to_output)

    prod_block = JCGEBlocks.activity_analysis(:activity, activities, commodities; params=params)
    cons_block = JCGEBlocks.consumer_endowment_cd(:consumers, consumers, commodities; params=params)
    market_block = JCGEBlocks.commodity_market_clearing(:markets, commodities, activities, consumers; params=params)
    numeraire = :PFX in commodities ? :PFX : commodities[1]
    numeraire_block = JCGEBlocks.numeraire(:numeraire, :commodity, numeraire, 1.0)

    closure = JCGECore.ClosureSpec(numeraire)
    scenario = JCGECore.ScenarioSpec(:baseline, Dict{Symbol,Any}())
    allowed_sections = JCGECore.allowed_sections()
    section_blocks = Dict(sym => Any[] for sym in allowed_sections)
    push!(section_blocks[:production], prod_block)
    push!(section_blocks[:households], cons_block)
    push!(section_blocks[:markets], market_block)
    push!(section_blocks[:closure], numeraire_block)
    sections = [JCGECore.section(sym, section_blocks[sym]) for sym in allowed_sections]
    required_nonempty = [:production, :households, :markets]
    return JCGECore.build_spec(
        name,
        sets,
        mappings,
        sections;
        closure=closure,
        scenario=scenario,
        required_sections=allowed_sections,
        allowed_sections=allowed_sections,
        required_nonempty=required_nonempty,
    )
end

"""
    _import_mpsge_data(model, data; name)

Internal: build a detailed RunSpec using precomputed data tables.
"""
function _import_mpsge_data(::MPSGEModel, data; name::String)
    sectors = data.sectors
    labor = data.labor

    sets = JCGECore.Sets(
        sectors,
        sectors,
        labor,
        [Symbol("households"), Symbol("government"), Symbol("foreign"), Symbol("investment")],
    )
    mappings = JCGECore.Mappings(Dict(i => i for i in sectors))

    trade_block = JCGEBlocks.trade_price_link(:trade_prices, sectors, (traded=data.traded, te=data.te, mcp=true))
    absorption_block = JCGEBlocks.absorption_sales(:absorption, sectors, (traded=data.traded, mcp=true))
    activity_price_block = JCGEBlocks.activity_price_io(:activity_price, sectors, sectors, (io=data.io, itax=data.itax, mcp=true))
    capital_price_block = JCGEBlocks.capital_price_composition(:capital_price, sectors, sectors, (imat=data.imat, mcp=true))
    production_block = JCGEBlocks.production_multilabor_cd(:production, sectors, labor; params=(ad=data.ad, alphl=data.alphl, wdist=data.wdist, mcp=true))
    labor_block = JCGEBlocks.labor_market_clearing(:labor_market, labor, sectors; params=(mcp=true,))
    cet_block = JCGEBlocks.cet_xxd_e(:cet, sectors, (traded=data.traded, at=data.at, gamma=data.gamma, rhot=data.rhot, mcp=true))
    export_block = JCGEBlocks.export_demand(:export, sectors, (traded=data.traded, eta=data.eta, e0=data.e0, pwe0=data.pwe0, mcp=true))
    armington_block = JCGEBlocks.armington_m_xxd(:armington, sectors, (traded=data.traded, delta=data.delta, ac=data.ac, rhoc=data.rhoc, mcp=true))
    nontraded_block = JCGEBlocks.nontraded_supply(:nontraded, sectors, (nontraded=data.nontraded, mcp=true))
    inventory_block = JCGEBlocks.inventory_demand(:inventory, sectors, (dstr=data.dstr, mcp=true))
    household_block = JCGEBlocks.household_share_demand(:household, sectors, (cles=data.cles, mcp=true))
    government_demand_block = JCGEBlocks.government_share_demand(:government_demand, sectors, (gles=data.gles, mcp=true))
    government_finance_block = JCGEBlocks.government_finance(:government_finance, sectors, (traded=data.traded, itax=data.itax, te=data.te, mcp=true))
    gdp_block = JCGEBlocks.gdp_income(:gdp, sectors, (mcp=true,))
    savings_block = JCGEBlocks.savings_investment(:savings, sectors, sectors, (depr=data.depr, kio=data.kio, imat=data.imat, mcp=true))
    market_block = JCGEBlocks.final_demand_clearing(:market, sectors, (mcp=true,))
    bop_block = JCGEBlocks.external_balance_var_price(:bop, sectors, (Sf=data.fsav0, mcp=true))

    start_vals = Dict{Symbol,Float64}()
    lower_vals = Dict{Symbol,Float64}()
    fixed_vals = Dict{Symbol,Float64}()

    dk0 = Dict{Symbol,Float64}()
    for j in sectors
        dk0[j] = sum(data.id0[i] * data.imat[(i, j)] for i in sectors)
    end

    for i in sectors
        start_vals[JCGEBlocks.global_var(:x, i)] = data.x0[i]
        start_vals[JCGEBlocks.global_var(:xd, i)] = data.xd0[i]
        start_vals[JCGEBlocks.global_var(:xxd, i)] = data.xd0[i] - data.e0[i]
        start_vals[JCGEBlocks.global_var(:cd, i)] = data.cles[i] * data.cdtot0
        start_vals[JCGEBlocks.global_var(:gd, i)] = data.gles[i] * data.gdtot0
        start_vals[JCGEBlocks.global_var(:id, i)] = data.id0[i]
        start_vals[JCGEBlocks.global_var(:dk, i)] = dk0[i]
        start_vals[JCGEBlocks.global_var(:dst, i)] = data.dst0[i]
        start_vals[JCGEBlocks.global_var(:int, i)] = data.int0[i]
        start_vals[JCGEBlocks.global_var(:pd, i)] = data.pd0[i]
        start_vals[JCGEBlocks.global_var(:pm, i)] = data.pm0[i]
        start_vals[JCGEBlocks.global_var(:pe, i)] = data.pe0[i]
        start_vals[JCGEBlocks.global_var(:p, i)] = data.pd0[i]
        start_vals[JCGEBlocks.global_var(:px, i)] = data.pd0[i]
        start_vals[JCGEBlocks.global_var(:pk, i)] = data.pd0[i]
        start_vals[JCGEBlocks.global_var(:pva, i)] = data.pva0[i]
        start_vals[JCGEBlocks.global_var(:pwe, i)] = data.pwe0[i]
        start_vals[JCGEBlocks.global_var(:pwm, i)] = data.pwm0[i]
        start_vals[JCGEBlocks.global_var(:tm, i)] = data.tm0[i]

        lower_vals[JCGEBlocks.global_var(:x, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:xd, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:pd, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:p, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:px, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:pk, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:int, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:cd, i)] = 0.0
        lower_vals[JCGEBlocks.global_var(:gd, i)] = 0.0
        lower_vals[JCGEBlocks.global_var(:id, i)] = 0.0
        lower_vals[JCGEBlocks.global_var(:dst, i)] = 0.0
    end

    for i in data.traded
        start_vals[JCGEBlocks.global_var(:m, i)] = data.m0[i]
        start_vals[JCGEBlocks.global_var(:e, i)] = data.e0[i]
        lower_vals[JCGEBlocks.global_var(:pm, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:xxd, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:m, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:e, i)] = 0.01
        lower_vals[JCGEBlocks.global_var(:pwe, i)] = 0.01
    end

    for lc in labor
        start_vals[JCGEBlocks.global_var(:wa, lc)] = data.wa0[lc]
        start_vals[JCGEBlocks.global_var(:ls, lc)] = data.ls0[lc]
        lower_vals[JCGEBlocks.global_var(:wa, lc)] = 0.01
    end

    for i in sectors, lc in labor
        start_vals[JCGEBlocks.global_var(:l, i, lc)] = data.xle[(i, lc)]
        lower_vals[JCGEBlocks.global_var(:l, i, lc)] = 0.01
    end

    start_vals[:er] = data.er
    start_vals[:gr] = data.gr0
    start_vals[:fsav] = data.fsav0
    start_vals[:mps] = data.mps0
    start_vals[:gdtot] = data.gdtot0

    start_vals[:tariff] = 76.548
    start_vals[:indtax] = 102.45
    start_vals[:savings] = 280.98

    y0 = sum(data.pva0[i] * data.xd0[i] for i in sectors) - sum(data.depr[i] * data.k0[i] for i in sectors)
    start_vals[:y] = y0
    start_vals[:hhsav] = data.mps0 * y0
    start_vals[:deprecia] = sum(data.depr[i] * data.pd0[i] * data.k0[i] for i in sectors)
    start_vals[:govsav] = data.gr0 - data.gdtot0
    lower_vals[:y] = 0.01

    fixed_vals[:fsav] = data.fsav0
    fixed_vals[:mps] = data.mps0
    fixed_vals[:gdtot] = data.gdtot0

    for i in sectors
        fixed_vals[JCGEBlocks.global_var(:k, i)] = data.k0[i]
        fixed_vals[JCGEBlocks.global_var(:pwm, i)] = data.pwm0[i]
    end

    for lc in labor
        fixed_vals[JCGEBlocks.global_var(:ls, lc)] = data.ls0[lc]
    end

    for i in data.traded
        fixed_vals[JCGEBlocks.global_var(:tm, i)] = data.tm0[i]
    end

    for i in data.nontraded
        fixed_vals[JCGEBlocks.global_var(:m, i)] = 0.0
        fixed_vals[JCGEBlocks.global_var(:e, i)] = 0.0
    end

    fixed_vals[JCGEBlocks.global_var(:l, Symbol("publiques"), Symbol("rural"))] = 0.0
    fixed_vals[JCGEBlocks.global_var(:l, Symbol("ag-subsist"), Symbol("urban-skil"))] = 0.0

    fixed_vals[:y] = y0

    init_block = JCGEBlocks.initial_values(:init, (start=start_vals, lower=lower_vals, fixed=fixed_vals))

    closure = JCGECore.ClosureSpec(:pwm)
    scenario = JCGECore.ScenarioSpec(:baseline, Dict{Symbol,Any}())
    allowed_sections = JCGECore.allowed_sections()
    section_blocks = Dict(sym => Any[] for sym in allowed_sections)
    push!(section_blocks[:production], production_block)
    push!(section_blocks[:factors], labor_block)
    push!(section_blocks[:government], government_demand_block, government_finance_block)
    push!(section_blocks[:savings], savings_block)
    push!(section_blocks[:households], household_block)
    push!(section_blocks[:prices], trade_block, absorption_block, activity_price_block, capital_price_block)
    push!(section_blocks[:external], bop_block)
    push!(section_blocks[:trade], cet_block, export_block, armington_block, nontraded_block)
    push!(section_blocks[:markets], inventory_block, gdp_block, market_block)
    push!(section_blocks[:init], init_block)
    sections = [JCGECore.section(sym, section_blocks[sym]) for sym in allowed_sections]
    required_nonempty = [:production, :households, :markets]
    return JCGECore.build_spec(
        name,
        sets,
        mappings,
        sections;
        closure=closure,
        scenario=scenario,
        required_sections=allowed_sections,
        allowed_sections=allowed_sections,
        required_nonempty=required_nonempty,
    )
end

"""
    _scalar_value(x)

Internal: coerce a scalar or MPSGE value to `Float64`.
"""
function _scalar_value(x)
    x isa Number && return Float64(x)
    return Float64(MPSGE.value(x))
end

"""
    _strip_index_name(sym)

Internal: strip `[idx]` suffixes from MPSGE symbol names and normalize separators.
"""
function _strip_index_name(sym::Symbol)
    s = String(sym)
    open_idx = findfirst('[', s)
    close_idx = findlast(']', s)
    if open_idx === nothing || close_idx === nothing || close_idx <= open_idx
        return sym
    end
    inner = s[(open_idx + 1):(close_idx - 1)]
    inner = replace(inner, "," => "_")
    return Symbol(inner)
end

end # module
